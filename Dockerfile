FROM perl:5.30.1

WORKDIR /app
EXPOSE 3000 8080

ENV MOJO_VERSION 8.33
COPY hub.pl /app/
RUN cpanm Mojolicious@"$MOJO_VERSION"
RUN cpanm Cache::FileCache Syntax::Keyword::Try  && rm -r /root/.cpanm
RUN cpanm IO::Socket::SSL  && rm -r /root/.cpanm

ENTRYPOINT ["hypnotoad", "--foreground", "/app/hub.pl"]
