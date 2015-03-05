# encoding: UTF-8
require 'csv'

module Jekyll
  class Reader
    attr_reader :site

    def initialize(site)
      @site = site
    end

    # Read Site data from disk and load it into internal data structures.
    #
    # Returns nothing.
    def read
      site.layouts = LayoutReader.new(site).read
      read_directories
      read_data(site.config['data_source'])
      read_collections
    end

    # Filter out any files/directories that are hidden or backup files (start
    # with "." or "#" or end with "~"), or contain site content (start with "_"),
    # or are excluded in the site configuration, unless they are web server
    # files such as '.htaccess'.
    #
    # entries - The Array of String file/directory entries to filter.
    #
    # Returns the Array of filtered entries.
    def filter_entries(entries, base_directory = nil)
      EntryFilter.new(site, base_directory).filter(entries)
    end

    # Read the entries from a particular directory for processing
    #
    # dir - The String relative path of the directory to read
    # subfolder - The String directory to read
    #
    # Returns the list of entries to process
    def get_entries(dir, subfolder)
      base = site.in_source_dir(dir, subfolder)
      return [] unless File.exist?(base)
      entries = Dir.chdir(base) { filter_entries(Dir['**/*'], base) }
      entries.delete_if { |e| File.directory?(site.in_source_dir(base, e)) }
    end


    # Determines how to read a data file.
    #
    # Returns the contents of the data file.
    def read_data_file(path)
      case File.extname(path).downcase
        when '.csv'
          CSV.read(path, {
                           :headers => true,
                           :encoding => site.config['encoding']
                       }).map(&:to_hash)
        else
          SafeYAML.load_file(path)
      end
    end

    # Recursively traverse directories to find posts, pages and static files
    # that will become part of the site according to the rules in
    # filter_entries.
    #
    # dir - The String relative path of the directory to read. Default: ''.
    #
    # Returns nothing.
    def read_directories(dir = '')
      base = site.in_source_dir(dir)
      entries = Dir.chdir(base) { filter_entries(Dir.entries('.'), base) }

      read_posts(dir)
      read_drafts(dir) if site.show_drafts
      site.posts.sort!
      limit_posts if site.limit_posts > 0 # limit the posts if :limit_posts option is set

      entries.each do |f|
        f_abs = site.in_source_dir(base, f)
        if File.directory?(f_abs)
          f_rel = File.join(dir, f)
          read_directories(f_rel) unless site.dest.sub(/\/$/, '') == f_abs
        elsif Utils.has_yaml_header?(f_abs)
          page = Page.new(site, site.source, dir, f)
          site.pages << page if site.publisher.publish?(page)
        else
          site.static_files << StaticFile.new(site, site.source, dir, f)
        end
      end

      site.pages.sort_by!(&:name)
      site.static_files.sort_by!(&:relative_path)
    end

    # Read all the files in <source>/<dir>/_posts and create a new Post
    # object with each one.
    #
    # dir - The String relative path of the directory to read.
    #
    # Returns nothing.
    def read_posts(dir)
      posts = read_content(dir, '_posts', Post)

      posts.each do |post|
        aggregate_post_info(post) if site.publisher.publish?(post)
      end
    end

    # Read all the files in <source>/<dir>/_drafts and create a new Post
    # object with each one.
    #
    # dir - The String relative path of the directory to read.
    #
    # Returns nothing.
    def read_drafts(dir)
      drafts = read_content(dir, '_drafts', Draft)

      drafts.each do |draft|
        if draft.published?
          aggregate_post_info(draft)
        end
      end
    end

    # Read all the content files from <source>/<dir>/magic_dir
    #   and return them with the type klass.
    #
    # dir - The String relative path of the directory to read.
    # magic_dir - The String relative directory to <dir>,
    #   looks for content here.
    # klass - The return type of the content.
    #
    # Returns klass type of content files
    def read_content(dir, magic_dir, klass)
      get_entries(dir, magic_dir).map do |entry|
        klass.new(site, site.source, dir, entry) if klass.valid?(entry)
      end.reject do |entry|
        entry.nil?
      end
    end

    # Read and parse all yaml files under <source>/<dir>
    #
    # Returns nothing
    def read_data(dir)
      base = site.in_source_dir(dir)
      read_data_to(base, site.data)
    end

    # Read and parse all yaml files under <dir> and add them to the
    # <data> variable.
    #
    # dir - The string absolute path of the directory to read.
    # data - The variable to which data will be added.
    #
    # Returns nothing
    def read_data_to(dir, data)
      return unless File.directory?(dir) && (!site.safe || !File.symlink?(dir))

      entries = Dir.chdir(dir) do
        Dir['*.{yaml,yml,json,csv}'] + Dir['*'].select { |fn| File.directory?(fn) }
      end

      entries.each do |entry|
        path = site.in_source_dir(dir, entry)
        next if File.symlink?(path) && site.safe

        key = sanitize_filename(File.basename(entry, '.*'))
        if File.directory?(path)
          read_data_to(path, data[key] = {})
        else
          data[key] = read_data_file(path)
        end
      end
    end

    # Read in all collections specified in the configuration
    #
    # Returns nothing.
    def read_collections
      site.collections.each do |_, collection|
        collection.read unless collection.label.eql?('data')
      end
    end

    def sanitize_filename(name)
      name.gsub!(/[^\w\s_-]+/, '')
      name.gsub!(/(^|\b\s)\s+($|\s?\b)/, '\\1\\2')
      name.gsub(/\s+/, '_')
    end

    # Aggregate post information
    #
    # post - The Post object to aggregate information for
    #
    # Returns nothing
    def aggregate_post_info(post)
      site.posts << post
    end

    private

    # Limits the current posts; removes the posts which exceed the limit_posts
    #
    # Returns nothing
    def limit_posts
      limit = site.posts.length < site.limit_posts ? site.posts.length : site.limit_posts
      site.posts = site.posts[-limit, limit]
    end

  end
end