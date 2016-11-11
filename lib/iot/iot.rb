require 'rss'
require 'open-uri'
require 'net/http'
require 'open-uri'
require 'yaml'
require 'fileutils'
require 'colorize'
require 'oga'
require 'pty'
require 'io/console'
require_relative 'keyboard_events'

class InOurTime
  ROOT            = File.expand_path '~/'
  HERE            = File.dirname(__FILE__)
  CONFIG_DIR      = '.in_our_time'
  CONFIG_NAME     = 'config.yml'
  IN_OUR_TIME     = File.join ROOT, CONFIG_DIR
  VERSION         = File.join HERE, '..','..','VERSION'
  DEFAULT_CONFIG  = File.join HERE, '..','..',CONFIG_NAME
  CONFIG          = File.join IN_OUR_TIME,CONFIG_NAME
  UPDATE_INTERVAL = 604800
  AUDIO_DIRECTORY = 'audio'
  RSS_DIRECTORY   = 'rss'

  class Tic
    def initialize
      @flag = false
      run
    end

    def kill
      Thread.kill(@th_tic) if @th_tic
    end

    def run
      @th_tic = Thread.new do
        loop do
          sleep 1
          @flag = true
        end
      end
    end

    def toc
      ret_val = @flag
      @flag = false
      ret_val
    end
  end

  def initialize
    @content = ''
    @programs = []
    @selected = 0
    clear
    print "\e[?25h"
    setup
    load_config
    load_version
    load_help_maybe
    opening_title
    check_remote
    parse_rss
    sort_titles
    version_display_wait
    STDIN.echo = false
    STDIN.raw!
    run
  end

  def do_events
    sleep 0.003
    sleep 0.1
  end

  def quit code = 0
    STDIN.echo = true
    STDIN.cooked!
    clear
    puts 'Quitting...'
    clear
    @key.kill
    @tic.kill
    exit code
  end

  def version_display_wait
    return if dev_mode?
    do_events while Time.now - @start_time < 1.5
  end

  def iot_print x, col = @text_colour
    @content << x.colorize(col) if @config[:colour]
    @content << x           unless @config[:colour]
  end

  def iot_puts x = '', col = @text_colour
    iot_print x, col
    iot_print "\n\r"
  end

  def clear_content
    @content.clear
  end

  def render
    clear
    $stdout << @content
  end

  def now
    Time.now.to_i
  end

  def setup
    @start_time = Time.now
    iot = IN_OUR_TIME
    audio = File.join iot, AUDIO_DIRECTORY
    pages = File.join iot, RSS_DIRECTORY
    Dir.mkdir iot unless Dir.exist? iot
    Dir.mkdir audio unless Dir.exist? audio
    return if Dir.exist?(pages)
    Dir.mkdir pages
    local_rss.map{|f| FileUtils.touch(File.join pages, f)}
  end

  def dev_mode?
    ENV['IN_OUR_TIME'] == 'development'
  end

  def puts_title colour
    title =
    %q{  _____          ____               _______ _
 |_   _|        / __ \             |__   __(_)
   | |  _ __   | |  | |_   _ _ __     | |   _ _ __ ___   ___
   | | | '_ \  | |  | | | | | '__|    | |  | | '_ ` _ \ / _ \
  _| |_| | | | | |__| | |_| | |       | |  | | | | | | |  __/
 |_____|_| |_|  \____/ \__,_|_|       |_|  |_|_| |_| |_|\___|
}

    title.split("\n").map{|l| iot_print(l + "\r\n", colour)} if(window_width > 61)
    iot_puts("In Our Time\r", colour) unless(window_width > 61)
    iot_puts
  end

  def opening_title
    return if dev_mode?
    puts_title :light_green
    render
    sleep 0.5
    clear_content
    puts_title @system_colour
    display_version
    render
  end

  def display_version
    iot_print("Loading ", :light_green) unless ARGV[0] == '-v' || ARGV[0] == '--version'
    iot_puts "In Our Time Player (#{@version})", :light_green
    quit if ARGV[0] == '-v' || ARGV[0] == '--version'
  end

  def load_version
    File.open(VERSION) {|f| @version = f.readline.strip}
  end

  def update_remote?
    now - @config[:update_interval] > @config[:last_update]
  end

  def create_config
    @config = YAML.load_file(DEFAULT_CONFIG)
    save_config
  end

  def init_theme
    theme = @config[:colour_theme]
    @selection_colour = @config[theme][:selection_colour]
    @count_sel_colour = @config[theme][:count_sel_colour]
    @count_colour     = @config[theme][:count_colour]
    @text_colour      = @config[theme][:text_colour]
    @system_colour    = @config[theme][:system_colour]
  end

  def theme_toggle
    theme = @config[:colour_theme]
    @config[:colour_theme] = theme == :light_theme ?
                               :dark_theme : :light_theme
    save_config
    init_theme
    redraw
  end

  def set_height
    height = window_height
    while(height -2 % 10 != 0) ; height -=1 ; end
    height = 10 if height < 10
    @page_height = height if(@config[:page_height] == :auto)
    @page_height = @config[:page_height] unless(@config[:page_height] == :auto)
  end

  def set_width
    width = window_width
    while(width % 10 != 0) ; width -=1 ; end
    width = 20 if width < 20
    @page_width = width - 1 if(@config[:page_width]  == :auto)
    @page_width = @config[:page_width] unless(@config[:page_width]  == :auto)
  end

  def window_height
    $stdout.winsize.first
  end

  def window_width
    $stdout.winsize[1]
  end

  def set_dimensions
    set_height
    set_width
  end

  def init_line_count
    @line_count = @page_height
  end

  def do_configs
    init_theme
    set_dimensions
    init_line_count
    @sort = @config[:sort]
  end

  def load_config
    create_config unless File.exist? CONFIG
    @config = YAML.load_file(CONFIG)
    do_configs
  end

  def save_config
    File.open(CONFIG, 'w') { |f| f.write @config.to_yaml}
  end

  def rss_addresses
    host = 'http://www.bbc.co.uk/programmes'
    [ "/b006qykl/episodes/downloads.rss",
      "/p01drwny/episodes/downloads.rss",
      "/p01dh5yg/episodes/downloads.rss",
      "/p01f0vzr/episodes/downloads.rss",
      "/p01gvqlg/episodes/downloads.rss",
      "/p01gyd7j/episodes/downloads.rss"
    ].collect{|page| host + page}
  end

  def local_rss
    [
      "culture.rss",
      "history.rss",
      "in_our_time.rss",
      "philosophy.rss",
      "religion.rss",
      "science.rss"
    ]
  end

  def fetch_uri uri, file
    open(file, "wb") do |f|
      open(uri) do |ur|
        f.write(ur.read)
      end
    end
  end

  def filename_from_title title
    temp = title.gsub(/[^0-9a-z ]/i, '').tr(' ', '_').strip + '.mp3'
    File.join IN_OUR_TIME, AUDIO_DIRECTORY, temp.downcase
  end

  def download_audio(program, addr)
    res = Net::HTTP.get_response(URI.parse(addr))
    case res
    when Net::HTTPOK
      File.open(filename_from_title(program[:title]) , 'wb') do |f|
        iot_print "writing #{filename_from_title(program[:title])}...", @system_colour
        render
        f.print(res.body)
        iot_puts " written.", @system_colour
        render
      end
      program[:have_locally] = true
    else
      iot_puts 'Download failed. Retrying...', @system_colour
      render
      nil
    end
  end

  def have_locally? title
    filename = filename_from_title(title)
    File.exist?(filename) ? true : false
  end

  def rss_files
    local_rss.map{|f| File.join IN_OUR_TIME, RSS_DIRECTORY, f }
  end

  def update
    clear_content
    iot_print "Checking rss feeds ", @system_colour
    local_rss.length.times do |count|
      iot_print '.', @system_colour
      render
      fetch_uri rss_addresses[count], rss_files[count]
    end
#    iot_puts
    @config[:last_update] = now
    save_config
  end

  def check_remote
    update if update_remote?
  end

  def uniquify_programs
    @programs = @programs.uniq{|pr| pr[:title]}
    return if @programs.uniq.length == @programs.length
    print_error_and_delay "Error ensuring Programs unique!"
    quit 1
  end

  def parse_rss
    rss_files.each do |file|
      @doc = Oga.parse_xml(File.open(file))
      titles    = @doc.xpath('rss/channel/item/title')
      subtitles = @doc.xpath('rss/channel/item/itunes:subtitle')
      summarys  = @doc.xpath('rss/channel/item/itunes:summary')
      durations = @doc.xpath('rss/channel/item/itunes:duration')
      dates     = @doc.xpath('rss/channel/item/pubDate')
      links     = @doc.xpath('rss/channel/item/link')

      0.upto(titles.length - 1) do |idx|
        program = {}
        program[:title] = titles[idx].text
        program[:subtitle] = subtitles[idx].text
        program[:summary]  = summarys[idx].text
        program[:duration] = durations[idx].text
        program[:date] = (dates[idx].text)[0..15]
        program[:link] = links[idx].text
        program[:have_locally] = have_locally?(titles[idx].text)
        @programs << program
      end
    end
    uniquify_programs
  end

  def select_program title
    @programs.map{|pr| return pr if(pr[:title].strip == title.strip)}
    nil
  end

  def sort_titles
    @sorted_titles = []
    @sorted_titles = @programs.collect { |pr| pr[:title] }
    @sorted_titles.sort! unless @sort == :age
  end

  def sort_selected title
    @sorted_titles.each_with_index do |st, idx|
      if st == title
        selected = idx
        idx += 1
        while idx % @page_height != 0
          idx += 1
        end
        return selected, idx
      end
    end
  end

  def list_selected title
    @selected, @line_count = sort_selected(title)
    redraw
  end

  def list_playing
    title = @sorted_titles[@selected]
    if title == @playing
      list_top
    else
      list_selected @playing
    end
  end

  def list_stopped
    if @selected == 0
      title = @sorted_titles[@last_selected || 0]
      list_selected title
    else
      list_top
    end
  end

  def list_key
    if @playing
      list_playing
    else
      list_stopped
    end
  end

  def list_top
    @last_selected = @selected
    @line_count = 0
    @selected = 0
    display_list :next_page
  end

  def sort_key
    title = @sorted_titles[@selected]
    toggle_sort
    list_selected title
  end

  def toggle_sort
    @sort = @sort == :age ? :alphabet : :age
    @config[:sort] = @sort
    save_config
    sort_titles
  end

  def redraw
    display_list :same_page
  end

  def date
    @programs.map {|pr| return pr[:date] if pr[:title] == @playing}
  end

  def pre_delay
    x = DateTime.strptime("Mon, 20 Jun 2016", '%a, %d %b %Y')
    y = DateTime.strptime(date, '%a, %d %b %Y')
    if y < x
      return '415' unless @playing == 'Abelard and Heloise'
      '0' if @playing == 'Abelard and Heloise'
    else
      '435'
    end
  end

  def player_cmd
    case @config[:mpg_player]
    when :mpg123
      "mpg123 --remote-err -Cqk#{pre_delay}"
    else
      "afplay"
    end
  end

  def clear
    system('clear') || system('cls')
  end

  def print_error_and_delay message, delay = 2
    iot_puts message, :red
    sleep delay
  end

  def run_program prg
    unless prg[:have_locally]
      retries = 0
      clear_content
      iot_puts "Fetching #{prg[:title]}", @system_colour
      render
      10.times do
        begin
          res = Net::HTTP.get_response(URI.parse(prg[:link]))
        rescue SocketError => e
          print_error_and_delay "Error: Failed to connect to Internet! (#{e.class})"
          render
          @no_play = true
          break
        end
        case res
        when Net::HTTPFound
          iot_puts 'redirecting...', @system_colour
          render
          @doc = Oga.parse_xml(res.body)
          redirect = @doc.css("body p a").text
          break if download_audio(prg, redirect)
          sleep 2
        else
          print_error_and_delay 'Error! Failed to be redirected!'
          render
          @no_play = true
        end
        retries += 1
      end
      if retries >= 10
        print_error_and_delay "Max retries downloading #{prg[:title]}"
        render
        @no_play = true
      end
    end
    unless @no_play
      @playing = prg[:title]
      window_title prg[:title]
      @cmd = player_cmd + ' ' + filename_from_title(@playing)
      @messages = []
      @p_out, @p_in, @pid = PTY.spawn(@cmd)
    end
    @no_play = nil
  end

  def window_title title = ''
    STDOUT.puts "\"\033]0;#{title}\007"
  end

  def reset
    @pid = nil
    @playing = nil
    @paused = nil
    window_title
    redraw
  end

  def write_player str
    begin
      @p_in.puts str
    rescue Errno::EIO
      reset
    end
  end

  def pause
    return unless control_play?
    @paused = @paused ? false : true
    write_player " "
    redraw
  end

  def control_play?
    @playing && (@config[:mpg_player] == :mpg123)
  end

  def forward
     write_player ":" if control_play?
  end

  def rewind
     write_player ";" if control_play?
  end

  def print_playing_maybe
    if @playing
      iot_print("Playing: ", @count_colour) unless @paused
      iot_print("Paused: ", @count_colour) if @paused
      iot_puts @playing, @selection_colour
    elsif @started.nil?
      @started = true
      iot_print "? or h for instructions", @text_colour
    end
  end

  def kill_audio
    return unless @playing
    @playing = nil
    return unless @pid.is_a?(Integer)
    Process.kill('QUIT', @pid)
    sleep 0.2
    reset
  end

  def idx_format idx
    sprintf("%03d", idx + 1)
  end

  def show_count_maybe idx
    if have_locally?(@sorted_titles[idx])
      iot_print idx_format(idx), @count_sel_colour if @config[:show_count]
    else
      iot_print idx_format(idx), @count_colour if @config[:show_count]
    end
    iot_print ' '
  end

  def draw_page
    clear_content
    if @line_count <= @sorted_titles.length
      @line_count.upto(@line_count + @page_height - 1) do |idx|
        if idx < @sorted_titles.length
          iot_print "> " if(idx == @selected) unless @config[:colour]
          show_count_maybe idx
          iot_puts @sorted_titles[idx], @selection_colour if (idx == @selected)
          iot_puts @sorted_titles[idx], @text_colour   unless(idx == @selected)
        end
      end
    else
      @line_count = 0
      0.upto(@page_height - 1) do |idx|
        iot_print "> ", @selection_colour if(idx == @selected)
        show_count_maybe(idx) unless @sorted_titles[idx].nil?
        iot_puts @sorted_titles[idx], @text_colour unless @sorted_titles[idx].nil?
      end
    end
    @line_count += @page_height
    print_playing_maybe
    render
  end

  def display_list action
    case action
    when :next_page
      draw_page
    when :previous_page
      if @line_count > 0
        @line_count -= (@page_height * 2)
      else
        @line_count = @sorted_titles.length
        @selected = @line_count
      end
      draw_page
    when :same_page
      @line_count -= @page_height
      draw_page
    end
  end

  def help_option?
    ARGV[0] == '-h' || ARGV[0] == '--help' || ARGV[0] == '-?'
  end

  def load_help_maybe
    return unless help_option?
    help
    quit
  end

  def help_screen
    []                                     <<
      " In Our Time Player (#{@version})"  <<
      "                                 "  <<
      " Play/Stop     - X or Enter      "  <<
      " Previous/Next - Down / Up       "  <<
      " Next Page     - SPACE           "  <<
      " Sort          - S               "  <<
      " Theme Toggle  - T               "  <<
      " List Top      - L               "  <<
      " Update        - U               "  <<
      " Info          - I               "  <<
      " Help          - H               "  <<
      " Quit          - Q               "  <<
      "                                 "  <<
      " mpg123 Controls:                "  <<
      "  Pause/Resume - P               "  <<
      "  Forward Skip - F               "  <<
      "  Reverse Skip - R               "  <<
      "                                 "  <<
      "Config: #{CONFIG}                "
  end

  def print_help
    iot_puts help_screen.map{|x|x.rstrip}.join("\n\r"), @system_colour
  end

  def help
    unless @help
      clear_content
      print_help
      print_playing_maybe
      @help = true
      render
    else
      redraw
      @help = nil
    end
  end

  def reformat info
    ['With','Guests','Producer','Contributors'].map do | x|
      [' ', ':'].map do |y|
        [x, x.upcase].map do |z|
          info.gsub!(z + y, "\n" + z + y)
        end
      end
    end
    info
  end

  def top_space info
    info.length - info.lstrip.length
  end

  def bottom_space? bottom
    bottom == ' '
  end

  def last_line? info, top
    info[top..-1].length < @page_width
  end

  def justify info
    pages = [[],[]]
    page = 0
    top = 0
    bottom = @page_width
    loop do
      shift = top_space info[top..bottom]
      top = top + shift
      bottom = bottom + shift
      loop do
        idx = info[top..bottom].index("\n")
        if idx
          pages[page] << info[top..top + idx]
          page = 1
          bottom = top + idx + @page_width + 1
          top = top + idx + 1
        else
          break if bottom_space? info[bottom]
          bottom -= 1
        end
      end
      if last_line? info, top
        pages[page] << info[top..-1].strip
        break
      end
      pages[page] << info[top..bottom]
      top = bottom
      bottom = bottom + @page_width
    end
    pages
  end

  def print_subtitle prg
    clear
    puts_title @system_colour
    justify(prg[:subtitle].gsub(/\s+/, ' '))[0].map{|x| iot_puts x}
    print_program_details prg
    @info = 1
    @page_count = 1
  end

  def print_program_details prg
    iot_puts "\nDate Broadcast: #{prg[:date]}"
    iot_puts "Duration:       #{prg[:duration].to_i/60} mins"
    iot_puts "Availability:   " +
             (prg[:have_locally] ? "Downloaded" : "Requires Download")
  end

  def print_info prg
    info = prg[:summary].gsub(/\s+/, ' ')
    count = 1
    justify(reformat(info))[0].each do |x|
      if (count > (@page_count - 1) * @page_height) &&
         (count <= @page_count * @page_height)
        iot_puts x
      end
      count += 1
    end
    if count <= @page_count * @page_height + 1
      @info = justify(reformat(info))[1] == [] ? -1 : 2
    else
      @page_count += 1
    end
  end

  def print_guests prg
    info = prg[:summary].gsub(/\s+/, ' ')
    clear
    justify(reformat(info))[1].map{|x| iot_puts x}
    @info = -1
  end

  def info
    clear_content
    case @info
    when nil
      prg = select_program @sorted_titles[@selected]
      print_subtitle prg
    when 1
      prg = select_program @sorted_titles[@selected]
      print_info prg
    when 2
      prg = select_program @sorted_titles[@selected]
      print_guests prg
    else
      redraw
      @info = nil
      return
    end
    render
  end

  def check_process
    if(@playing && @pid.is_a?(Integer))
      begin
        write_player( "\e")
        if @pid.is_a? Integer
          Process.kill 0, @pid
        end
      rescue Errno::ESRCH
        reset
      end
    else
      @pid = nil
    end
  end

  def page_forward
    @selected = @line_count
    display_list :next_page
  end

  def page_back
    @selected = @line_count - @page_height * 2
    @selected = @selected < 0 ? 0 : @selected
    list_selected @sorted_titles[@selected]
  end

  def previous
    @selected -= 1 if @selected > 0
    if @selected >= @line_count -
                    @page_height
      redraw
    else
      display_list :previous_page
    end
  end

  def next
    @selected += 1
    if @selected <= @line_count - 1
      redraw
    else
      display_list :next_page
    end
  end

  def play
    if @playing
      kill_audio
    else
      kill_audio
      title = @sorted_titles[@selected]
      pr = select_program title
      run_program pr
      redraw
    end
  end

  def update_key
      update
      parse_rss
      sort_titles
      @line_count = 0
      @selected = 0
      display_list :next_page
  end

  def quit_key
    kill_audio
    quit
  end

  def do_action ip
    case ip
    when :pause, :forward, :rewind, :list_key, :page_forward, :page_back,
         :previous, :next, :play, :sort_key, :theme_toggle, :update_key,
         :info, :help, :quit_key
      self.send ip
    end
  end

  def reset_info_maybe ip
    @info = nil unless ip == :info
    @help = nil unless ip == :help
  end

  def run
    ip = ''
    @tic = Tic.new
    @key = KeyboardEvents.new
    redraw

    loop do
      loop do
        ip = @key.read
        break unless ip == :no_event
        check_process if @tic.toc
        do_events
      end
      reset_info_maybe ip
      do_action ip
      do_events
    end
  end
end

InOurTime.new if __FILE__ == $0
