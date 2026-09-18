require "./spec_helper"

describe Myip do
  it "works" do
    false.should eq(false)
  end

  it "starts a spinner on Crystal's current execution context" do
    spinner = Term::Spinner.new(interval: 1.millisecond)

    spinner.run do
      spinner.success
    end

    spinner.done?.should be_true
  end
end
