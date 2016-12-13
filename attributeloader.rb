require 'asciidoctor/extensions' unless RUBY_ENGINE == 'opal'
require 'asciidoctor/path_resolver'
require 'asciidoctor/cli'
require 'asciidoctor'

class AttributeLoaderPreprocessor < Asciidoctor::Extensions::Preprocessor

  def self.parse_config_file
    # load config file
    cliargs = Asciidoctor::Cli::Options.parse! ARGV.clone
    resolver = Asciidoctor::PathResolver.new
    # Specified by -a config-file=...
    if cliargs[:attributes].has_key? "config-file"
      confile = resolver.system_path cliargs[:attributes]["config-file"], resolver.working_dir
    # No config-file specified, use ~/.asciidoctor.conf if exists
    elsif File.file? resolver.system_path('.asciidoctor.conf', File.expand_path('~'))
      confile = resolver.system_path('.asciidoctor.conf', File.expand_path('~'))
    else  # Use default file
      confile = resolver.system_path('config-default.yml', File.dirname(__FILE__))
    end
    unless File.file? confile
      $stderr.puts "\nWarning: cannot find config file: #{confile}. Asciidoctor will use default attributes.\n" if cliargs[:verbose] > 0
      return nil
    end
    # Prepare attributes from config file
    require 'yaml'
    YAML.load_file(confile)
  end


  def process document, reader

    opts = self.class.parse_config_file

    if opts.nil? || opts.empty?
      return reader
    end

    cliargs = Asciidoctor::Cli::Options.parse! ARGV.clone
    resolver = Asciidoctor::PathResolver.new
    attrib = Hash.new

    # Common attributes
    if opts.has_key? 'common-attributes'
      opts['common-attributes'].each { |k, v| attrib[k] = v unless cliargs[:attributes].has_key? k }
    end

    # Parse theme attributes
    theme = document.attributes['theme'] || opts['default-theme']
    if opts['themes'].has_key? theme
      opts['themes'][theme].each { |k, v| attrib[k] = v unless cliargs[:attributes].has_key? k }
    else
      $stderr.puts "\nWarning: Cannot find theme: #{theme}, ignoring theme." if cliargs[:verbose] > 0
    end

    # Force common source highlighter theme and dir attributes
    if attrib.has_key? 'highlighter-theme' || document.attributes.has_key?('highlighter-theme')
      attrib['highlighter-theme'] = document.attributes['highlighter-theme'] || attrib['highlighter-theme']
      attrib.delete 'highlightjs-theme'
      attrib.delete 'prettify-theme'
    end

    if attrib.has_key?('highlighterdir') || document.attributes.has_key?('highlighterdir')
      attrib['highlighterdir'] = document.attributes['highlighterdir'] || attrib['highlighterdir']
      attrib.delete 'highlightjsdir'
      attrib.delete 'prettifydir'
    end

    highlighter = document.attributes['source-highlighter'] || attrib['source-highlighter']
    hl_theme = {'highlightjs' => 'highlightjs-theme', 'highlight.js' => 'highlightjs-theme', 'prettify' => 'prettify-theme'}
    hl_dir = {'highlightjs' => 'highlightjsdir', 'highlight.js' => 'highlightjsdir', 'prettify' => 'prettifydir'}
    
    base_dir = document.attributes['common-dir'] || opts['common-dir'] || '' # Must be absolute dir if use
    
    # Set document attributes
    attrib.each do |k, v|
      case k
      when 'highlighter-theme'
        document.attributes[hl_theme[highlighter]] = v unless document.attributes.has_key?( hl_theme[highlighter] )
      when 'highlighterdir'
        v = resolver.system_path(v, base_dir) if resolver.is_root? base_dir
        document.attributes[hl_dir[highlighter]] = v unless document.attributes.has_key?( hl_dir[highlighter] )
      when 'stylesdir' # Use /dir$/  for all other dirs if necessary
        v = resolver.system_path(v, base_dir) if resolver.is_root? base_dir
        document.attributes[k] = v
      when 'stylesheet'
        document.attributes[k] = v.end_with?(".css") ? v : v + '.css'
      when String
          document.attributes[k] = v
      when true
          document.attributes[k] = ''
      when false
          document.attributes.delete(k)
      end
    end
    reader
  end
end

Asciidoctor::Extensions.register do
  preprocessor AttributeLoaderPreprocessor
end

# Load other extensions
resolver = Asciidoctor::PathResolver.new
opts = AttributeLoaderPreprocessor.parse_config_file
if opts && opts.has_key? 'extensions'
  opts['extensions'].each do |ext|
    ext['enabled'].each { |e| require resolver.system_path(e, ext['base_dir']) }
  end
end
