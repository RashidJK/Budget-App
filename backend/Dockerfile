# Build an ahead-of-time binary, then ship it on a tiny runtime image.
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

# The scratch runtime carries only the Dart AOT runtime + our binary.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
ENV PORT=8080
EXPOSE 8080
CMD ["/app/bin/server"]
