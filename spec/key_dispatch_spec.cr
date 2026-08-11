require "./spec_helper"
require "../src/app"

def key(char : Char) : Tui::KeyEvent
  Tui::KeyEvent.new(char: char)
end

def key(key : Tui::Key) : Tui::KeyEvent
  Tui::KeyEvent.new(key: key)
end

describe "Cresium::App keyboard dispatch (stopwatch)" do
  it "start/pause with [space], lap with [l]" do
    app = Cresium::App.new
    app.on_event(key(' ')).should be_true
    app.active_stopwatch.running?.should be_true

    app.on_event(key('l')).should be_true
    app.active_stopwatch.laps.size.should eq(1)
  end

  it "creates and deletes stopwatches with [n] and [d]" do
    app = Cresium::App.new
    app.on_event(key('n'))
    app.stopwatches.size.should eq(2)

    app.on_event(key('d'))
    app.stopwatches.size.should eq(1)
  end

  it "does not delete the last stopwatch" do
    app = Cresium::App.new
    app.on_event(key('d'))
    app.stopwatches.size.should eq(1)
  end

  it "ignores unhandled keys" do
    app = Cresium::App.new
    app.on_event(key('z')).should be_false
  end
end

describe "Cresium::App keyboard dispatch (timer, editing)" do
  it "types hh:mm:ss digit by digit then sets it with [enter]" do
    app = Cresium::App.new
    app.on_capture(Tui::KeyEvent.new(key: Tui::Key::Tab)) # switch to the timer screen

    "000010".each_char { |c| app.on_event(key(c)) }
    app.timer_buffer.should eq("000010")

    app.on_event(key(Tui::Key::Enter))
    app.timer_editing?.should be_false
    app.active_timer.set?.should be_true
  end

  it "erases a digit with [backspace]" do
    app = Cresium::App.new
    app.on_capture(Tui::KeyEvent.new(key: Tui::Key::Tab))

    app.on_event(key('5'))
    app.timer_buffer.should eq("000005")
    app.on_event(key(Tui::Key::Backspace))
    app.timer_buffer.should eq("000000")
  end

  it "cancels the input with [escape]" do
    app = Cresium::App.new
    app.on_capture(Tui::KeyEvent.new(key: Tui::Key::Tab))

    app.on_event(key('5'))
    app.on_event(key(Tui::Key::Escape))
    app.timer_buffer.should eq("000000")
  end

  it "creates and deletes timers with [n] and [d]" do
    app = Cresium::App.new
    app.on_capture(Tui::KeyEvent.new(key: Tui::Key::Tab))

    app.on_event(key('n'))
    app.timers.size.should eq(2)

    app.on_event(key('d'))
    app.timers.size.should eq(1)
  end

  it "navigates between timers with [↑↓]" do
    app = Cresium::App.new
    app.on_capture(Tui::KeyEvent.new(key: Tui::Key::Tab))
    app.on_event(key('n'))
    app.on_event(Tui::KeyEvent.new(key: Tui::Key::Up))
    app.timers.first.should eq(app.active_timer)
  end
end

describe "Cresium::App keyboard dispatch (timer, running)" do
  it "starts the countdown automatically once the duration is set" do
    app = Cresium::App.new
    app.on_capture(Tui::KeyEvent.new(key: Tui::Key::Tab))
    "000005".each_char { |c| app.on_event(key(c)) }
    app.on_event(key(Tui::Key::Enter))
    app.timer_editing?.should be_false
    app.active_timer.running?.should be_true

    app.on_event(key('7')) # ignored: the timer is running
    app.timer_editing?.should be_false

    app.on_event(key(' ')) # pause
    app.active_timer.running?.should be_false

    app.on_event(key('r')) # reset -> back to editing
    app.timer_editing?.should be_true
  end
end
