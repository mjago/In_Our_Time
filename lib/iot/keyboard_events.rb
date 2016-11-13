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
    Thread.abort_on_exception = true
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
              @event = :page_back    if str == "D"
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
    @event =
      case str
      when "\e"
        @mode = :escape
        :no_event
      when 'a', 'A'
        :sort_key
      when 'd', 'D'
        :download_key
      when 'f', 'F'
        :forward
      when 'h', 'H'
        :help
      when 'i', 'I'
        :info
      when 'l', 'L'
        :list_key
      when 'e', 'E'
        :enqueue
      when 'p', 'P', ' '
        :pause
      when 'q', 'Q', "\u0003", "\u0004"
        :quit_key
      when 'r', 'R'
        :rewind
      when 's', 'S'
        :shuffle_key
      when 'n', 'N'
        :next_program
      when 't', 'T'
        :theme_toggle
      when 'u', 'U'
        :update_key
      when 'x', 'X', "\r"
        :play
      when '?'
        :search
      else
        :no_event
      end
  end
end

