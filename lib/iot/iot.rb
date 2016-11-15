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
  CONFIG_DIR      = '.in_our_time'.freeze
  CONFIG_NAME     = 'config.yml'.freeze
  IN_OUR_TIME     = File.join ROOT, CONFIG_DIR
  VERSION         = File.join HERE, '..','..','VERSION'
  DEFAULT_CONFIG  = File.join HERE, '..','..',CONFIG_NAME
  CONFIG          = File.join IN_OUR_TIME,CONFIG_NAME
  UPDATE_INTERVAL = 604800
  AUDIO_DIRECTORY = 'audio'.freeze
  RSS_DIRECTORY   = 'rss'.freeze

  class Tic

    def initialize
      @flag = false
      init_processes
      run
    end

    def init_processes
      @processes =
        { process: {
            timeout: 10,
            value:   0 },
          playing_time: {
            timeout: 1,
            value:   0 },
          ended: {
            timeout: 1,
            value:   0 }
        }
    end

    def inc_processes
      @processes.each { |process| process[:value] += 1 }
    end

    def kill
      Thread.kill(@th_tic) if @th_tic
    end

    def timeout? type
      @processes[type]
      return unless @processes[type][:value] > @processes[type][:timeout]
      @processes[type][:value] = 0
      true
    end

    def process
      timeout? :process
    end

    def playing_time
      timeout? :playing_time
    end

    def ended
      timeout? :ended
    end

    def run
      Thread.abort_on_exception = true
      @th_tic = Thread.new do
        loop do
          sleep 0.1
          @processes[:process][:value] += 1
          @processes[:playing_time][:value] += 1
          @processes[:ended][:value] += 1
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

  class PlayTime

    def initialize(fmt, dur)
      @format = fmt
      @duration = dur
#      @duration = 0 #dur
      @start_time = Time.now
      update
    end

    def format(fmt)
      @format = fmt
    end

    def changed?
      ! unchanged?
    end

    def read
      store
      format_time
    end

    def ended?
      (@duration + 20) < @seconds
    end

    def unchanged?
      (update == stored) || paused?
    end

    def stored
      @stored
    end

    def plural x
      x == 1 ? '' : 's'
    end

    def mins
      @seconds / 60
    end

    def secs
      @seconds % 60
    end

    def format_minutes
      mins.to_s + ' min' + plural(mins)
    end

    def format_secs
      return '' unless @format == :mins_secs
      ' ' + secs.to_s + ' sec' + plural(secs)
    end

    def format_time
      return '' if @format == :none
      ' (' + format_minutes + format_secs + ')'
    end

    def update
      @seconds = (Time.now - @start_time).to_i
    end

    def store
      @stored = @seconds
    end

    def pause
      @paused = Time.now
    end

    def paused?
      @paused
    end

    def unpause
      @start_time = @start_time + (Time.now - @paused)
      @paused = false
    end

    def forward
      @start_time -= 1.5
    end

    def rewind
      @start_time += 1.5
    end
  end

  def initialize
    @queued = Array.new
    @content = String.new
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
    @key.kill if @key
    @tic.kill if @tic
    sleep 0.5
    STDIN.echo = true
    STDIN.cooked!
    puts "\n\n#{@error_msg}" if @error_msg
    puts 'Quitting...'.freeze
    sleep 0.5
    exit code
  end

  def version_display_wait
    return if dev_mode?
    do_events while Time.now - @start_time < 1.5
  end

  def iot_print x, col = @text_colour, now = false
    content = String.new
      content << x.colorize(col) if @config[:colour]
      content << x unless @config[:colour]
      unless now
        @content << content
      else
        $stdout << content
      end
  end

  def iot_puts x = '', col = @text_colour, now = false
    iot_print x, col, now
    iot_print "\n\r", now
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
    ENV['IN_OUR_TIME'] == 'development'.freeze
  end

  def puts_title colour
    title =
      %q{  _____          ____               _______ _
 |_   _|        / __ \             |__   __(_)
   | |  _ __   | |  | |_   _ _ __     | |   _ _ __ ___   ___
   | | | '_ \  | |  | | | | | '__|    | |  | | '_ ` _ \ / _ \
  _| |_| | | | | |__| | |_| | |       | |  | | | | | | |  __/
 |_____|_| |_|  \____/ \__,_|_|       |_|  |_|_| |_| |_|\___|
}.freeze

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
    while(((height - 2) % 10) != 0) ; height -= 1 ; end
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
    filename = "/episodes/downloads.rss"
    host = 'http://www.bbc.co.uk/programmes'
    [ "/b006qykl", "/p01drwny", "/p01dh5yg",
      "/p01f0vzr", "/p01gvqlg", "/p01gyd7j"
    ].collect{|page| host + page + filename}
  end

  def local_rss
    [ "culture.rss", "history.rss", "in_our_time.rss",
      "philosophy.rss", "religion.rss", "science.rss"]
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
        iot_puts "writing #{File.basename(filename_from_title(program[:title]))}", @system_colour
        render
        sleep 0.2
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
    clear
    iot_print "Checking rss feeds ", @system_colour, :now
    local_rss.length.times do |count|
      iot_print '.', @system_colour, :now
      fetch_uri rss_addresses[count], rss_files[count]
    end
    @config[:last_update] = now
    save_config
  end

  def check_remote
    update if update_remote?
  end

  def uniquify_programs
    @programs.uniq!{|pr| pr[:title]}
    return if @programs.uniq.length == @programs.length
    print_error_and_delay "Error ensuring Programs unique!"
    quit 1
  end

  def tags
    ['title', 'itunes:subtitle',
     'itunes:summary', 'itunes:duration',
     'pubDate', 'link']
  end

  def build_program(bin)
    title = bin[tags[0]].shift.text
    { title:    title,
      subtitle: bin[tags[1]].shift.text,
      summary:  bin[tags[2]].shift.text,
      duration: bin[tags[3]].shift.text,
      date:     bin[tags[4]].shift.text[0..15],
      link:     bin[tags[5]].shift.text,
      have_locally: have_locally?(title)
    }
  end

  def build_programs bin
    bin['title'].size.times do
      @programs << build_program(bin)
    end
  end

  def item_path name
    "rss/channel/item/#{name}"
  end

  def clear_programs
    @programs = []
  end

  def parse_rss
    clear_programs
    rss_files.each do |file|
      @doc = Oga.parse_xml(File.open(file))
      bin = {}
      tags.each do |tag|
        bin[tag] = [] if bin[tag].nil?
        bin[tag] = @doc.xpath(item_path(tag))
      end
      build_programs(bin)
    end
    uniquify_programs
    @titles_count = @programs.length
  end

  def select_program title
    @programs.map{|pr| return pr if(pr[:title].strip == title.strip)}
    nil
  end

  def sort_titles
    @sorted_titles = @programs.collect { |pr| pr[:title] }
    @sorted_titles.sort_by!(&:downcase) unless @sort == :age
  end

  def get_line_count idx
    idx += 1
    while idx % @page_height != 0
      idx += 1
    end
    idx
  end

  def sort_selected title
    @sorted_titles.each_with_index do |st, sel|
      if st == title
        return sel, get_line_count(sel)
      end
    end
  end

  def draw_selected
    @line_count = get_line_count(@selected)
    redraw
  end

  def draw_by_title title
    @selected, @line_count = sort_selected(title)
    redraw
  end

  def title_focus
    @playing ? @playing : (@sorted_titles[@last_selected || 0])
  end

  def top_selected
    @selected == 0
  end

  def end_selected
    @selected == @titles_count - 1
  end

  def top_title_focus
    title_focus == @sorted_titles.first
  end

  def end_title_focus
    title_focus == @sorted_titles.last
  end

  def top_or_end?
    top_selected || end_selected
  end

  def store_selected
    @last_selected = @selected
  end

  def top_or_end_title_focus
    top_title_focus || end_title_focus
  end

  def list_key
    if top_or_end?
      if top_or_end_title_focus
        if top_selected
          list_end
        else
          list_top
        end
      else
        draw_by_title title_focus
      end
    else
      store_selected
      list_top_or_end
    end
  end

  def list_top_or_end
    @list_top = @list_top? nil : true
    if @list_top
      list_top
    else
      list_end
    end
  end

  def list_top
    @selected = 0
    draw_selected
  end

  def list_end
    @selected = @titles_count - 1
    draw_selected
  end

  def sort_key
    title = @sorted_titles[@selected]
    toggle_sort
    draw_by_title title
  end

  def toggle_sort
    @sort = @sort == :age ? :alphabet : :age
    @config[:sort] = @sort
    save_config
    sort_titles
  end

  def redraw
    @line_count -= @page_height
    draw_page
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

  def use_mpg123?
    @config[:mpg_player] == :mpg123
  end

  def get_player
    return 'afplay' if @config[:mpg_player] == :afplay
    @config[:mpg_player].to_s
  end

  def player_cmd
    if use_mpg123?
      "mpg123 --remote-err -Cqk#{pre_delay}"
    else
      get_player
    end
  end

  def clear
    system('clear') || system('cls')
  end

  def print_error_and_delay message, delay = 2
    iot_puts message, :red
    sleep delay
  end

  def get_search_results search_term
    distances = {}
    @sorted_titles.each do |title|
      title.split(' ').each do |word|
        if distances[title].nil?
          distances[title] = Levenshtein::distance(search_term, word)
        else
          distances[title] =
            distances[title] >
            Levenshtein::distance(search_term, word.downcase)   ?
              Levenshtein::distance(search_term, word.downcase) :
              distances[title]
        end
      end
    end
    results = distances.sort_by{ |k, v| v }
    results.shuffle! if search_term == ''
    results
  end

  def print_search_results results
    puts
    puts "0: Search Again!"
    puts
    5.times do |count|
      print "#{count + 1}: "
      puts results[count][0]
    end
    puts
  end

  def display_search_choice results, choice
    @key = KeyboardEvents.new
    begin
      if choice.to_i > 0 && choice.to_i < 6
        draw_by_title(results[choice.to_i - 1][0])
        return
      end
    end
    redraw
  end

  def get_search_term
    iot_puts "Enter Search Term or just Return for Random:", @system_colour, :now
    puts
    puts
    print "Search Term: "
    gets.chomp
  end

  def get_search_choice
    print "Enter Choice: "
    temp = $stdin.getch.chomp
    temp == '0' ? :search_again : temp
  end

  def search_init
    @key.kill
    sleep 0.2
    STDIN.echo = true
    STDIN.cooked!
    clear
    sleep 0.2
  end

  def search
    choice = ''
    results = []
    loop do
      search_init
      search_term = get_search_term
      results = get_search_results(search_term)
      print_search_results(results)
      choice = get_search_choice
      break unless choice == :search_again
    end
    display_search_choice results, choice
  end

  def download prg
    return if prg[:have_locally]
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

  # Cross-platform way of finding an executable in the $PATH.
  #
  #   which('ruby') #=> /usr/bin/ruby

  def which(cmd)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each { |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      }
    end
    return nil
  end

  def unknown_player cmd
    @error_msg = "Error: Unknown MPG Player: #{cmd}\r"
    quit 1
  end

  def init_countdown(duration)
    @play_time = PlayTime.new(:mins_secs, duration)
  end

  def run_program prg
    unless @no_play
      @playing = prg[:title]
      player = player_cmd.split(' ').first
      unknown_player(player) unless which(File.basename player)
      window_title prg[:title]
      cmd = player_cmd + ' ' + filename_from_title(@playing)
      @messages = []
      init_countdown prg[:duration].to_i
      @p_out, @p_in, @pid = PTY.spawn(cmd)
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
    @play_time.pause if @paused
    @play_time.unpause unless @paused
    write_player " "
    redraw
  end

  def control_play?
    @playing && use_mpg123?
  end

  def forward
    return unless control_play?
    write_player ":"
    @play_time.forward
  end

  def rewind
    return unless control_play?
    write_player ";"
    @play_time.rewind
  end

  def instructions
    iot_print "Type", @system_colour
    iot_print " h ", :light_green
    iot_print "for instructions", @system_colour
  end

  def print_playing
    iot_print("Playing: ", @count_colour)
  end

  def print_paused
    iot_print("Paused: ", @count_colour)
  end

  def print_play_time
    iot_puts(@playing + @play_time.read, @selection_colour)
  end

  def print_playing_maybe
    if @playing
      print_playing unless @paused
      print_paused if @paused
      print_play_time
    elsif @started.nil?
      @started = true
      instructions
    end
  end

  def kill_audio
    loop do
      return unless @playing
      begin
        break unless @pid.is_a?(Integer)
        Process.kill('QUIT', @pid)
        _, status = Process.wait2 @pid
        break if status.exited?
      rescue Errno::ESRCH
        break
      end
      sleep 0.2
    end
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
    if @line_count <= @titles_count
      @line_count.upto(@line_count + @page_height - 1) do |idx|
        if idx < @titles_count
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

  def help_option?
    ARGV[0] == '-h' || ARGV[0] == '--help' || ARGV[0] == '-?'
  end

  def load_help_maybe
    return unless help_option?
    @config[:colour] = false
    help
    puts
    exit 0
  end

  def help_screen
    []                                     <<
      " In Our Time Payer (#{@version})"  <<
      "                                 "  <<
      " Play/Stop          - Enter/X    "  <<
      " Next/Prev          - Up/Down    "  <<
      " Next/Prev Page     - Right/Left "  <<
      " Arrange            - A          "  <<
      " Search             - ?          "  <<
      " Theme Toggle       - T          "  <<
      " List Top-End-Focus - L          "  <<
      " Update             - U          "  <<
      " Download           - D          "  <<
      " Enqueue            - E          "  <<
      " Shuffle Play       - S          "  <<
      " Shuffle Next       - N          "  <<
      " Info               - I          "  <<
      " Help               - H          "  <<
      " Quit               - Q          "  <<
      " mpg123 Control     -            "  <<
      "   Pause/Resume     - P/Spacebar "  <<
      "   Forward Skip     - F          "  <<
      "   Reverse Skip     - R          "  <<
      "                                 "  <<
      "Config: #{CONFIG}                "
  end

  def title_xy; [0,0]                          end
  def main_xy; [1, help_screen.size - 7]       end
  def mpg_xy; [help_screen.size - 6, -2]       end
  def cfg_xy; [help_screen.size - 1, -1]       end
  def help_partial(x); help_screen[x[0]..x[1]] end
  def help_title; help_partial(title_xy)       end
  def help_main; help_partial(main_xy)         end
  def help_cfg;  help_partial(cfg_xy)          end

  def help_mpg
    scr = help_partial(mpg_xy)
    scr[0].rstrip! << ' (enabled)  ' if     use_mpg123?
    scr[0].rstrip! << ' (disabled) ' unless use_mpg123?
    scr
  end

  def help_colour scr
    case scr
    when :mpg
      return @selection_colour unless use_mpg123?
      @count_colour if use_mpg123?
    when :cfg
      @system_colour
    when :title
      @system_colour
    else
      @text_colour
    end
  end

  def rstrip_maybe scr
    self.rstrip unless scr == :mpg
  end

  def help_render scr
    txt = send "help_#{scr}"
    iot_puts txt.map{|x| x}.join("\n\r"), help_colour(scr)
  end

  def print_help
    help_render :title
    help_render :main
    help_render :mpg
#    help_render :cfg
  end

  def help
    unless @help
      clear_content
      print_help
      print_playing_maybe unless help_option?
      @help = true
      render
    else
      redraw
      @help = nil
    end
  end

  def reformat info
    ['With','Guests','Producer','Contributors'].map do |x|
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

  def page_forward
    return unless @line_count < @titles_count
    @selected = @line_count
    draw_selected
  end

  def page_back
    @selected = @line_count - @page_height * 2
    @selected = @selected < 0 ? 0 : @selected
    draw_selected
  end

  def previous
    return if @selected <= 0
    @selected -= 1
    draw_selected
  end

  def next
    return if @selected >= (@titles_count - 1)
    @selected += 1
    draw_selected
  end

  def play
    title = @sorted_titles[@selected]
    playing = @playing
    prg = select_program(title)
    download prg unless playing
    download prg if playing && (playing != title)
    kill_audio
    return unless (! playing) || (playing != title)
    run_program prg
    redraw
  end

  def update_key
    update
    parse_rss
    sort_titles
    @selected = 0
    draw_selected
  end

  def download_key
    title = @sorted_titles[@selected]
    pr = select_program title
    download pr
    draw_selected
  end

  def enqueue
    @queued << @sorted_titles[@selected]
  end

  def next_program
    kill_audio
  end

  def shuffle_key
    @queued = @sorted_titles.shuffle
  end

  def quit_key
    kill_audio
    quit
  end

  def do_action ip
    case ip
    when :pause, :forward, :rewind, :list_key, :page_forward, :page_back,
         :previous, :next, :play, :sort_key, :theme_toggle, :update_key,
         :info, :help, :quit_key, :search, :download_key, :enqueue,
         :next_program, :shuffle_key
      self.send ip
    end
  end

  def reset_info_maybe ip
    @info = nil unless ip == :info
    @help = nil unless ip == :help
  end

  def ping_player
    write_player("\e")
  end

  def check_player_process
    Process.kill 0, @pid
  end

  def check_process
    if(@playing && @pid.is_a?(Integer))
      begin
        write_player("\e")
        sleep 0.1
        if @pid.is_a? Integer
          check_player_process
        end
      rescue Errno::ESRCH
        kill_audio
      end
    else
      unless @queued.empty?
        title = @queued.shift
        prg = select_program(title)
        download prg
        run_program(prg)
        draw_by_title title
      end
    end
  end

  def check_finished
    return unless @playing
    return unless @play_time.ended?
    kill_audio
  end

  def check_tic
    return unless @tic.toc
    check_process if @tic.process
    check_finished if @tic.ended
    return unless @info.nil?
    return unless @help.nil?
    check_playing_time if @tic.playing_time
   end

  def check_playing_time
    return unless @playing
    return unless @play_time.changed?
    redraw
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
        check_tic
        do_events
      end
      reset_info_maybe ip
      do_action ip
      do_events
    end
  end
end

InOurTime.new if __FILE__ == $0
