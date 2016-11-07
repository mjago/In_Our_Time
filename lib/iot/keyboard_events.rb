class KeyboardEvents
  def initialize
    update_wait
    @mode = :normal
    @event = :no_event
    @alive = true
    run
  end

  def reset
    STDIN.flush
  end

  def do_events
    sleep 0.001
  end

  def kill
    @alive = nil
    Thread.kill(@key) if @key
  end

  def update_wait
    @wait = Time.now + 0.02
  end

  def reset_event
    @event = :no_event unless @event == :quit_key
  end

  def read
    update_wait unless @event == :no_event
    ret_val = @event
    reset_event
    ret_val
  end

  def run
    @key = Thread.new do
      while @event != :quit_key
        str = ''
        loop do
          str = STDIN.getch
          next if Time.now < @wait
          if str == "\e"
            @mode = :escape
          else
            case @mode
            when :escape
              @mode =
                str == "[" ? :escape_2 : :normal
            when :escape_2
              @event = :previous     if str == "A"
              @event = :next         if str == "B"
              @event = :page_forward if str == "C"
              @event = :previous     if str == "D"
              @mode  = :normal
            else
              break if @event == :no_event
            end
          end
          do_events
        end
        match_event str
      end
    end
  end

  def match_event str
    case str
    when "\e"
      @mode = :escape
    when "l",'L'
      @event = :list_key
    when "u",'U'
      @event = :update_key
    when ' '
      @event = :page_forward
    when "q",'Q', "\u0003", "\u0004"
      @event = :quit_key
    when 'p', 'P'
      @event = :pause
    when 'f', 'F'
      @event = :forward
    when 'r', 'R'
      @event = :rewind
    when 's', 'S'
      @event = :sort_key
    when 't', 'T'
      @event = :theme_toggle
    when 'x', 'X', "\r"
      @event = :play
    when 'i', 'I'
      @event = :info
    when '?', 'h', 'H'
      @event = :help
    else
      return @event = :no_event
    end
  end
end

