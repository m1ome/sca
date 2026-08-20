# The sca umbrella as one release: domain plus all three endpoints.
#
#     docker build -t sca .
#     docker run --rm -e SECRET_KEY_BASE=… -e DATABASE_URL=… -p 4000-4002:4000-4002 sca
#     docker run --rm -e … sca /app/bin/migrate    # migrations, as their own step
#
# Pinned down to the debian date: the same build in six months, the same image.
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.3
ARG DEBIAN_VERSION=trixie-20260803

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}-slim"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Their own layer, keyed on mix.lock. An umbrella needs every child's mix.exs
# to see what the project consists of.
COPY mix.exs mix.lock ./
COPY apps/sca/mix.exs apps/sca/
COPY apps/sca_api/mix.exs apps/sca_api/
COPY apps/sca_web/mix.exs apps/sca_web/
COPY apps/sca_admin/mix.exs apps/sca_admin/
COPY apps/sca_ui/mix.exs apps/sca_ui/
RUN mix deps.get --only $MIX_ENV
RUN mkdir -p config

# Config affects how dependencies compile, so it comes first.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY apps apps

RUN mix assets.deploy

RUN mix compile

# Read at boot, so it stays out of the compile layer.
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    MIX_ENV="prod"

WORKDIR /app

RUN chown nobody /app
USER nobody

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/sca ./

EXPOSE 4000 4001 4002

CMD ["/app/bin/sca", "start"]
