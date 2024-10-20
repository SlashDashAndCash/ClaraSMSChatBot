FROM ruby:3

WORKDIR /usr/src/app

COPY Gemfile ./
RUN apt-get update; \
    apt-get upgrade; \
    apt-get clean; \
    bundle install

CMD ["/usr/local/bin/ruby", "clara.rb"]

