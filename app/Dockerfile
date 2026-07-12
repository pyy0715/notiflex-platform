FROM golang:1.26.4-alpine AS builder

ARG VERSION=dev

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w -X main.version=${VERSION}" -o /notiflex-api .

FROM scratch

COPY --from=builder /notiflex-api /notiflex-api

EXPOSE 8080

ENTRYPOINT ["/notiflex-api"]
