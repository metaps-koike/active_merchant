require 'test_helper'

# == Description
# Credorax supports both Credit Card based operations, and those where a token is provided
# which represents Credit Card details previously stored with Credorax
#
# This test class will test the options were CREDIT CARD details are supplied.
#
class RemoteCredoraxTest < Test::Unit::TestCase
  def setup
    @gateway = CredoraxGateway.new(fixtures(:credorax))

    @credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                               })
    @declined_card = credit_card('400030001111222',
                                 {:brand => nil,
                                  :verification_value => '123'
                                 })
    @amount = 10000 # This is 'cents', so 100 Euros

    @billing_address = {
        company:  'Widgets Inc',
        city:     'Tokyo',
        state:    '13', # TOKYO - http://www.unece.org/fileadmin/DAM/cefact/locode/Subdivision/jpSub.htm
        zip:      '163-6038',
        country:  'JP'
    }

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        billing_address: @billing_address,
        description: 'Store Item123', # Limited to 13 characters
        d2: 'd2 test value',
        invoice: 'tracking_id'
    }
  end

  def test_failure_store
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = @amount
    assert_raise(ArgumentError){  @gateway.store('111111', @options) }
  end

  def test_successful_purchase
    @options[:email] = 'noone@example.com'
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
  end

  def test_failed_purchase
    @options[:email] = 'noone@example.com'
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'Card+cannot+be+identified (-9)', response.message
  end

  def test_successful_authorize_and_capture
    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value',
        invoice: 'tracking_id'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
  end

  def test_failed_authorize
    @options[:email] = 'noone@example.com'
    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
  end

  def test_partial_capture
    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value',
        invoice: 'tracking_id'
    }
    assert capture = @gateway.capture(@amount-1000, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
  end

  def test_failed_capture
    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value',
        invoice: 'tracking_id'
    }
    bad_auth = {
        authorization_code: auth.authorization[:authorization_code],
        response_id: auth.authorization[:response_id],
        transaction_id: auth.authorization[:transaction_id],
        token: auth.authorization[:token],
        previous_request_id: ''
    }
    assert capture = @gateway.capture(nil, bad_auth, options)
    assert_failure capture

  end

  def test_successful_refund_from_sale
    @options[:email] = 'noone@example.com'
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :sale,
        invoice: 'tracking_id'
    }
    assert refund = @gateway.refund(nil, purchase.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_successful_refund_from_capture
    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value',
        invoice: 'tracking_id'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :capture,
        invoice: 'tracking_id'
    }
    assert refund = @gateway.refund(nil, capture.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_successful_refund_for_post_clearing
    @options[:email] = 'noone@example.com'
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :basic_post_clearing_credit,
        invoice: 'tracking_id'
    }
    assert refund = @gateway.refund(nil, purchase.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_failed_refund
    @options[:email] = 'noone@example.com'
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :sale,
        invoice: 'tracking_id'
    }
    bad_auth = {
        authorization_code: purchase.authorization[:authorization_code],
        response_id: purchase.authorization[:response_id],
        transaction_id: purchase.authorization[:transaction_id],
        token: purchase.authorization[:token],
        previous_request_id: ''
    }
    response = @gateway.refund(nil, bad_auth, options)
    assert_failure response
  end

  def test_successful_void
    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 void value',
        invoice: 'tracking_id'
    }
    assert void = @gateway.void(auth.authorization, options)
    assert_success void
    assert_equal 'Transaction+has+been+executed+successfully.', void.message
  end

  def test_failed_void
    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 void value',
        invoice: 'tracking_id'
    }
    bad_auth = {
        authorization_code: auth.authorization[:authorization_code],
        response_id: auth.authorization[:response_id],
        transaction_id: auth.authorization[:transaction_id],
        token: auth.authorization[:token],
        previous_request_id: ''
    }
    assert void = @gateway.void(bad_auth, options)
    assert_failure void
  end

  def test_failed_verify
    assert_raise(NotImplementedError){ @gateway.verify(@credit_card, @options) }
  end

  def test_invalid_login
    gateway = CredoraxGateway.new(
        merchant_id: 'fake',
        md5_cipher_key: 'fake',
        name_on_statement: 'fake',
        live_url: 'http://www.example.com'
    )
    @options[:email] = 'noone@example.com'
    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end
end
