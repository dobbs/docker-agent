FROM alpine
RUN apk --no-cache update \
 && apk --no-cache upgrade \
 && apk add openssh
RUN ssh-keygen -A
RUN mkdir /root/.ssh /root/bin
WORKDIR /root
COPY docker-agent /usr/local/bin
VOLUME ["/tmp"]
EXPOSE 22
CMD ["docker-agent"]
