FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN flutter pub get
COPY . .
RUN flutter build web --wasm --release \
    --dart-define=LOQUI_API_BASE=https://loqui-api.mathiiis.de
RUN printf 'E404:index.html\n' > httpd.conf
FROM lipanski/docker-static-website:2.4.0
COPY --from=build /app/build/web ./
COPY --from=build /app/httpd.conf ./httpd.conf
EXPOSE 3000
