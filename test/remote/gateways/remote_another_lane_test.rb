require 'test_helper'

class RemoteAnotherLaneTest < Test::Unit::TestCase
  def setup

    # test
#    require 'logger'
#    logger = ::Logger.new('log/active_merchant.log')
#    ActiveMerchant::Billing::Gateway.logger = logger

    @gateway = AnotherLaneGateway.new(fixtures(:another_lane))


    # Do not change this value because 210 JPY is specified by gatway company.
    @amount = 210

    # valid acctual credit card is needed for testing APIs
    @credit_card   = credit_card('4000000000000000')
    @declined_card = credit_card('4000000000000000', :year => Time.now.year - 1)


    @options = {
      billing_address: address,
      customer_id: 'customer_id',
      customer_password: 'password',
    }

    @options_quick = {
      customer_id: 'customer_id',
      customer_password: 'password',
    }
  end


  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_match(/(Approved|OK)/i, response.message)
  end

  def test_successful_quick_purchase
    response = @gateway.purchase(@amount, nil, @options_quick)
    assert_success response
    assert_match(/(Approved|OK)/i, response.message)
  end

  # To test this, need to execute live mode.
  def test_successful_capture
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert void = @gateway.capture(@amount, response.authorization)
    assert_success void
  end

  # Test server returns succeed even if sending invalid request.
  def test_failed_purchase
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
  end

  def test_successful_update
    response = @gateway.update(@options[:customer_id], @options[:customer_password], @credit_card, nil, @options)
    assert_success response
    assert_match(/thanks/, response.message)
  end

  def test_successful_update_mail
    response = @gateway.update(@options[:customer_id], @options[:customer_password], nil, 'foo@example.com', @options)
    assert_success response
    assert_match(/thanks/, response.message)
  end

  # To test this, need to execute live mode.
  def test_successful_void
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert void = @gateway.void(response.authorization)
    assert_success void
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
  end

  def test_invalid_login
    gateway = AnotherLaneGateway.new(
      site_id: 'test',
      site_password: 'test'
    )
    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end
end
