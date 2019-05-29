FROM perl:5.28.0-slim
WORKDIR /app
RUN apt-get update && \
    apt-get install -y build-essential libssl-dev zlib1g-dev openssl nano vim

WORKDIR /app
COPY cpanfile /app
RUN cpanm --installdeps --notest .

COPY chunky-dump.pl /app

ENTRYPOINT ["perl", "/app/chunky-dump.pl"]
