require 'test_helper'

# == Description
# Credorax supports both Credit Card based operations, and those where a token is provided
# which represents Credit Card details previously stored with Credorax
#
# This test class will test the options were tokens are used. Credit Card details will only be supplied
# in the initial calls to generate the token.
#
# Execute this test with.... bundle exec rake test:remote TEST=test/remote/gateways/remote_credorax_token_variant_test.rb


class RemoteCredoraxTokenVariantTest < Test::Unit::TestCase
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
    @bad_cvv_card = credit_card('400030001111222',
                                {:brand => nil,
                                 :verification_value => '1234',
                                 :month => 3,
                                 :year => (Time.now.year + 1),
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
        d2: 'd2 test value',
        invoice: 'tracking_id'
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

  def test_successful_store_with_disable_padding_normal_name
    init_options = fixtures(:credorax)
    init_options[:cardholder_name_padding] = false
    gateway = CredoraxGateway.new(init_options)
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534
    response = gateway.store(@credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_successful_store_with_short_name
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534

    short_name_credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                                :name => 'Yu'
                               })

    response = @gateway.store(short_name_credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_successful_store_with_short_two_word_name
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534

    short_name_credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                                :name => 'Yu X'
                               })

    response = @gateway.store(short_name_credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_successful_store_with_short_name_custom_padding
    init_options = fixtures(:credorax)
    init_options[:cardholder_name_padding_character] = '_'
    gateway = CredoraxGateway.new(init_options)
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534

    short_name_credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                                :name => 'Yu'
                               })

    response = gateway.store(short_name_credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_successful_store_with_four_characters_name_custom_padding
    init_options = fixtures(:credorax)
    init_options[:cardholder_name_padding_character] = '_'
    gateway = CredoraxGateway.new(init_options)
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534

    short_name_credit_card = credit_card('4037660000001115',
                                         {
                                             :brand => nil,
                                             :verification_value => '123',
                                             :month => 3,
                                             :year => (Time.now.year + 1),
                                             :first_name => 'ABCD',
                                             :last_name => ' ',
                                         })
    response = gateway.store(short_name_credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_successful_store_with_blank_name_custom_padding
    init_options = fixtures(:credorax)
    init_options[:cardholder_name_padding_character] = '_'
    gateway = CredoraxGateway.new(init_options)
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534

    short_name_credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                                :name => ''
                               })

    response = gateway.store(short_name_credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_failure_store
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = @amount
    response = @gateway.store(@declined_card, @options)
    assert_failure response
    assert_equal 'Card+cannot+be+identified (-9)', response.message
  end

  def test_failure_store_due_to_short_name_padding_off
    init_options = fixtures(:credorax)
    init_options[:cardholder_name_padding] = false
    gateway = CredoraxGateway.new(init_options)
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534
    short_name_credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                                :name => 'Yu'
                               })
    assert_raise(ArgumentError, "billing contact name must be at least than 5 characters") do
      gateway.store(short_name_credit_card, @options)
    end
  end

  def test_failure_store_due_to_blank_name_padding_off
    init_options = fixtures(:credorax)
    init_options[:cardholder_name_padding] = false
    gateway = CredoraxGateway.new(init_options)
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = 32433534
    short_name_credit_card = credit_card('4037660000001115',
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                                :name => ''
                               })
    assert_raise(ArgumentError, "billing contact name must be at least than 5 characters") do
      gateway.store(short_name_credit_card, @options)
    end
  end

  def test_failure_due_to_bad_cvv
    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = @amount
    assert_raise(ArgumentError){ @gateway.store(@bad_cvv_card, @options) }
  end

  def test_successful_purchase
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123', # Limited to 13 characters
        d2: 'd2 purchase value',
        invoice: 'tracking_id'
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
        d2: 'd2 purchase value',
        invoice: 'tracking_id'
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
        d2: 'd2 purchase value',
        invoice: 'tracking_id'
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
        d2: 'd2 capture value',
        invoice: 'tracking_id'
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
        d2: 'd2 auth value',
        invoice: 'tracking_id'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

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
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value',
        invoice: 'tracking_id'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

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

  def test_successful_refund_from_capture
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value',
        invoice: 'tracking_id'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value',
        invoice: 'tracking_id'
    }
    capture = @gateway.capture(nil, auth.authorization, options)

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

  def test_successful_refund_from_sale
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123', # Limited to 13 characters
        d2: 'd2 purchase value',
        invoice: 'tracking_id'
    }
    purchase = @gateway.purchase(@amount, store.authorization[:token], options)

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

  def test_successful_refund_from_sale_post_clearing
    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123', # Limited to 13 characters
        d2: 'd2 purchase value',
        invoice: 'tracking_id'
    }
    purchase = @gateway.purchase(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :post_clearing_credit,
        invoice: 'tracking_id'
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
        d2: 'd2 auth value',
        invoice: 'tracking_id'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 capture value',
        invoice: 'tracking_id'
    }
    capture = @gateway.capture(nil, auth.authorization, options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 refund value',
        refund_type: :capture,
        invoice: 'tracking_id'
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
        d2: 'd2 auth value',
        invoice: 'tracking_id'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

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
    store = @gateway.store(@credit_card, @options)

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        d2: 'd2 auth value',
        invoice: 'tracking_id'
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], options)

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
end
