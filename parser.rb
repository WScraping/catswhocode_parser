require 'rubygems'
require 'net/http'
require 'nokogiri'
require 'byebug'
require 'benchmark/ips'

module Parsers
  module CatsWhoCode
    class PostsParser
      attr_accessor :blog_links, :data

      BASE_URL = "http://www.catswhocode.com/blog/page/"

      def initialize(limit = 30)
        @blog_links = []
        @data = []
        @limit = limit.abs
      end

      def call_threads
        threads = []
        @limit.times do |n|
          threads << Thread.new { scrape_post_links(n) }
        end
        threads.each(&:join)

        # it may be failing but i don't have a lot of time
        @blog_links.each do |link|
          threads << Thread.new { scrape_post_data(link) }
        end
        # run scraping of each post link in own thread
        threads.each(&:join)
        @data
      end

      def call
        @limit.times do |n|
          scrape_post_links(n)
        end

        # it may be failing but i don't have a lot of time
        @blog_links.each do |link|
          scrape_post_data(link)
        end
        # run scraping of each post link in own thread
        @data
      end

      private

      def scrape_post_links(number)
        doc = get_doc_from("#{BASE_URL}#{number}")
        # here we have all articles links from page
        doc.xpath(post_link_xpath).each do |link|
          # alse we make checking that link from this blog
          if link[:href] =~ /https?:\/\/[w.]*catswhocode\.com\/blog/
            @blog_links << link[:href]
          end
        end
      end

      # it will be used in few places :)
      def get_doc_from(url)
        Nokogiri::HTML(Net::HTTP.get(URI(url))) do |config|
          config.strict.nonet.noblanks.noerror
        end
      end

      def scrape_post_data(link)
        doc = get_doc_from(link)
        image = doc.xpath('//article/p/img')
        image_link = image.first['data-lazy-src'] if image.first

        option = { url: link,
                   title: doc.xpath(post_link_xpath).text,
                   image: image_link,
                   body: doc.xpath('//article/p|//article/pre').map(&:to_html).join }
        @data << option
      end

      def post_link_xpath
        "//article/header/h2/a"
      end
    end
  end
end

Benchmark.ips do |x|
  x.config(time: 10, warmup: 5)
  x.report("Thread") { Parsers::CatsWhoCode::PostsParser.new.call_threads }
  x.report("Simple") { Parsers::CatsWhoCode::PostsParser.new.call }

  x.compare!
end

=begin
➜  catswhocode_parser git:(master)  ruby /ssd/projects/catswhocode_parser/parser.rb
Warming up --------------------------------------
              Thread     1.000  i/100ms
              Simple     1.000  i/100ms
Calculating -------------------------------------
              Thread      0.087  (± 0.0%) i/s -      1.000  in  11.514291s
              Simple      0.014  (± 0.0%) i/s -      1.000  in  73.424957s

Comparison:
              Thread:        0.1 i/s
              Simple:        0.0 i/s - 6.38x slower

=end
