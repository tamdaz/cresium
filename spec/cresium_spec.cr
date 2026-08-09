require "./spec_helper"

describe Cresium::Stopwatch do
  it "is zero? right after initialization" do
    Cresium::Stopwatch.new.zero?.should be_true
  end

  it "is running? after start, and no longer zero?" do
    sw = Cresium::Stopwatch.new
    sw.start
    sw.running?.should be_true
    sw.zero?.should be_false
  end

  it "is paused? after start then pause" do
    sw = Cresium::Stopwatch.new
    sw.start
    sw.pause
    sw.paused?.should be_true
    sw.running?.should be_false
    sw.zero?.should be_false
  end

  it "is zero? again after reset" do
    sw = Cresium::Stopwatch.new
    sw.start
    sw.pause
    sw.reset
    sw.zero?.should be_true
  end

  it "records a lap only while running" do
    sw = Cresium::Stopwatch.new
    sw.lap
    sw.laps.should be_empty

    sw.start
    sw.lap
    sw.laps.size.should eq(1)
  end

  it "clears laps on reset" do
    sw = Cresium::Stopwatch.new
    sw.start
    sw.lap
    sw.reset
    sw.laps.should be_empty
  end
end

describe Cresium::Timer do
  it "is not paused? nor expired? before being armed" do
    timer = Cresium::Timer.new
    timer.paused?.should be_false
    timer.expired?.should be_false
  end

  it "is paused? once armed but not started" do
    timer = Cresium::Timer.new
    timer.arm 5.seconds
    timer.paused?.should be_true
  end

  it "is running? and not paused? once started" do
    timer = Cresium::Timer.new
    timer.arm 5.seconds
    timer.start
    timer.running?.should be_true
    timer.paused?.should be_false
  end

  it "is expired? once the duration has elapsed" do
    timer = Cresium::Timer.new
    timer.arm 0.001.seconds
    timer.start
    sleep 0.05.seconds
    timer.expired?.should be_true
    timer.paused?.should be_false
  end
end

describe Cresium::Theme do
  it "resolves stopwatch colors by state" do
    sw = Cresium::Stopwatch.new
    Cresium::Theme.stopwatch_color(sw).should eq(Cresium::Theme::ALERT)

    sw.start
    Cresium::Theme.stopwatch_color(sw).should eq(Cresium::Theme::RUNNING)

    sw.pause
    Cresium::Theme.stopwatch_color(sw).should eq(Cresium::Theme::PAUSED)
  end

  it "resolves timer colors by state, including the editing phase" do
    timer = Cresium::Timer.new
    Cresium::Theme.timer_color(timer, true).should eq(Cresium::Theme::NEUTRAL)

    timer.arm 5.seconds
    Cresium::Theme.timer_color(timer, false).should eq(Cresium::Theme::PAUSED)

    timer.reset
    timer.arm 0.001.seconds
    timer.start
    sleep 0.05.seconds
    Cresium::Theme.timer_color(timer, false).should eq(Cresium::Theme::ALERT)
  end
end
