# A `hh:mm[:ss]` digit input buffer with a movable cursor, shared by the
# manual-duration and target-time inputs on the timer screen.
class Cresium::DigitInput
  getter buffer : String
  getter cursor_pos : Int32
  getter? cursor_active : Bool

  @last_digit : Int32

  def initialize(@digits : Int32) : Nil
    @last_digit = @digits - 1
    @buffer = "0" * @digits
    @cursor_pos = @last_digit
    @cursor_active = false
  end

  # Resets to a blank buffer (or `buffer`, e.g. a single freshly-typed digit).
  def reset(buffer : String = "0" * @digits) : Nil
    @buffer = buffer
    @cursor_pos = @last_digit
    @cursor_active = false
  end

  # Types `c` at the cursor (if active) or shifts it in from the right.
  def type_digit(c : Char) : Nil
    if @cursor_active
      @buffer = @buffer.sub(@cursor_pos, c)
      @cursor_pos = Math.min(@last_digit, @cursor_pos + 1)
    else
      @buffer = @buffer[1..] + c
    end
  end

  # Erases the digit at the cursor (if active) or shifts a `0` in from the right.
  def backspace : Nil
    if @cursor_active && @cursor_pos > 0
      @cursor_pos -= 1
      @buffer = @buffer.sub(@cursor_pos, '0')
    else
      @buffer = '0' + @buffer[0..-2]
    end
  end

  def move_left : Nil
    @cursor_pos = @cursor_active ? Math.max(0, @cursor_pos - 1) : @last_digit
    @cursor_active = true
  end

  def move_right : Nil
    @cursor_pos = @cursor_active ? Math.min(@last_digit, @cursor_pos + 1) : @last_digit
    @cursor_active = true
  end
end
