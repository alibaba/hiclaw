ARG HIGRESS_REGISTRY=higress-registry.cn-hangzhou.cr.aliyuncs.com

FROM ${HIGRESS_REGISTRY}/higress/golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY *.go ./
COPY proxy/ ./proxy/
COPY backend/ ./backend/
COPY api/ ./api/
RUN CGO_ENABLED=0 go build -o /hiclaw-orchestrator .

FROM ${HIGRESS_REGISTRY}/higress/alpine:3.20
COPY --from=builder /hiclaw-orchestrator /usr/local/bin/
EXPOSE 2375
CMD ["hiclaw-orchestrator"]
