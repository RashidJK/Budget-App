# Build an ahead-of-time binary, then ship it on a slim runtime with CA certs
# (the server makes outbound HTTPS calls to Google and Airtel).
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /app/schema.sql /app/schema.sql
ENV PORT=8080
EXPOSE 8080
CMD ["/app/bin/server"]
