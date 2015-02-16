require 'test_helper'

# == Description
# Credorax supports both Credit Card based operations, and those where a token is provided
# which represents Credit Card details previously stored with Credorax
#
# This test class will test the options were tokens are used. Credit Card details will only be supplied
# in the initial calls to generate the token.
#


class RemoteCredoraxTokenVariantTest < Test::Unit::TestCase
  def setup
    @gateway = CredoraxGateway.new(fixtures(:credorax))

    @credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                               })
    @declined_card = credit_card('4000300011112220',
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
        invoice: 'merchant invoice',
        d2: 'd2 test value'
    }
  end

  def test_successful_store
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534
    response = @gateway.store(@credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_failure_store
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = @amount
    response = @gateway.store(@declined_card, @options)
    assert_failure response
    assert_equal 'Card+cannot+be+identified', response.message
  end

  def test_successful_purchase

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123', # Limited to 13 characters
        d2: 'd2 purchase value'
    }
    response = @gateway.purchase(@amount, store.authorization[:token], options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
  end

  def test_successful_purchase_transaction_scoped_dba

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123', # Limited to 13 characters
        merchant: 'METAPS-CC', # Limited to 25 characters
        d2: 'd2 purchase value'
    }
    response = @gateway.purchase(@amount, store.authorization[:token], options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
  end

  def test_failed_purchase

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123', # Limited to 13 characters
        d2: 'd2 purchase value'
    }

    response = @gateway.purchase(@amount, '111111111', options)
    assert_failure response

  end

  def test_successful_authorize_and_capture

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message
    assert_not_nil auth.authorization[:token]

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
  end

  def test_failed_authorize
    @options[:email] = 'noone@example.com'
    @options[:create_token] = true
    response = @gateway.authorize(@amount, '111111111', @options)
    assert_failure response
  end

  def test_partial_capture
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value'
    }
    assert capture = @gateway.capture(@amount-1000, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
  end

  def test_failed_capture
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value'
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

  def test_successful_refund_from_capture
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value'
    }
    capture = @gateway.capture(nil, auth.authorization, options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :capture
    }
    assert refund = @gateway.refund(nil, capture.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_successful_refund_from_sale
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123', # Limited to 13 characters
        d2: 'd2 purchase value'
    }
    purchase = @gateway.purchase(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :sale
    }
    assert refund = @gateway.refund(nil, purchase.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_failed_refund
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value'
    }
    capture = @gateway.capture(nil, auth.authorization, options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :capture
    }
    bad_auth = {
        authorization_code: auth.authorization[:authorization_code],
        response_id: auth.authorization[:response_id],
        transaction_id: auth.authorization[:transaction_id],
        token: auth.authorization[:token],
        previous_request_id: ''
    }
    assert refund = @gateway.refund(nil, bad_auth, options)
    assert_failure refund
  end

  def test_successful_void
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 void value'
    }
    assert void = @gateway.void(auth.authorization, options)
    assert_success void
    assert_equal 'Transaction+has+been+executed+successfully.', void.message
  end

  def test_failed_void
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 void value'
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

end
