require 'test_helper'

# == Description
# This test class runs the tests required to pass certification
#
class RemoteCredoraxCertificationTest < Test::Unit::TestCase
  def setup
    @gateway = CredoraxGateway.new(fixtures(:credorax))
  end

  def test_sale_za

    order_id = Time.now.getutc.strftime("%Y%m%d%H%M%S")

    card = credit_card('4358525174655353',
                {:brand => '',
                 :verification_value => '123',
                 :month => 12,
                 :year => 2015,
                 :first_name => 'John',
                 :last_name => 'Tailor',
                })
    options = {
        order_id: order_id,
        description: 'Store Item123',
        d2: '1694BEB',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    response = @gateway.purchase(10000, card, options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message

    # Test failure with duplicate ID
    options = {
        order_id: order_id,
        description: 'Store Item123',
        d2: '1694BDE',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    response = @gateway.purchase(10000, card, options)
    assert_failure response

    # Test failure of sale void
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BE2',
        refund_type: :sale
    }
    bad_auth = {
        authorization_code: '0N0NE0',
        response_id: response.authorization[:response_id],
        transaction_id: response.authorization[:transaction_id],
        token: response.authorization[:token],
        previous_request_id: response.authorization[:previous_request_id]
    }
    assert refund = @gateway.refund(nil, bad_auth, options)
    assert_failure refund

    # Test unknown result code
    options = {
        order_id: order_id,
        description: 'Store Item123',
        d2: '1694BE3',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    response = @gateway.purchase(10000, card, options)
    assert_failure response

    # Test unknown response reason code
    options = {
        order_id: order_id,
        description: 'Store Item123',
        d2: '1694BE4',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    response = @gateway.purchase(10000, card, options)
    assert_failure response
    assert_not_equal '00', response.authorization[:response_reason_code]

    'No response from Gateway'
    options = {
        order_id: order_id,
        description: 'Store Item123',
        d2: '1694BE1',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    response = @gateway.purchase(10000, card, options)
    assert_failure response
    assert_not_equal '-7', response.authorization[:error_code]

    # Unregistered Currency
    options = {
        order_id: order_id,
        description: 'Store Item123',
        d2: '1694BDF',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        currency: 'AFN'
    }
    response = @gateway.purchase(10000, card, options)
    assert_failure response
    assert_not_equal '-7', response.authorization[:error_code]

  end

  def test_unregistered_card
    card = credit_card('4358525174655353',
                       {:brand => 6,
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        d2: '1694BE0',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        currency: 'AFN'
    }
    response = @gateway.purchase(10000, card, options)
    assert_failure response
    assert_not_equal '-7', response.authorization[:error_code]
  end


  def test_timeout
    card = credit_card('4358525174655353',
                       {:brand => '',
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        d2: '1694BE5',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    assert_raise(ActiveMerchant::ConnectionError){ @gateway.purchase(10000, card, options) }

  end


  def test_authorization_zg
    card = credit_card('4358525174655353',
                       {:brand => '',
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        d2: '1694BEC',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    auth = @gateway.authorize(10000, card, options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message
  end

  def test_capture_zh
    card = credit_card('4358525174655353',
                       {:brand => '',
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BEC'
    }
    auth = @gateway.authorize(10000, card, options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BED'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message

  end

  def test_auth_void_zj
    card = credit_card('4358525174655353',
                       {:brand => '',
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BEC'
    }
    auth = @gateway.authorize(10000, card, options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BEE'
    }
    assert void = @gateway.void(auth.authorization, options)
    assert_success void
    assert_equal 'Transaction+has+been+executed+successfully.', void.message
  end

  def test_referral_credit_zh
    card = credit_card('4358525174655353',
                       {:brand => '',
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BEC'
    }
    auth = @gateway.authorize(10000, card, options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BED'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BEF',
        refund_type: :basic_post_clearing_credit
    }
    assert refund = @gateway.refund(nil, capture.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message

  end

  def test_sale_void_zf
    card = credit_card('4358525174655353',
                       {:brand => '',
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        d2: '1694BEB',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
    }
    response = @gateway.purchase(10000, card, options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BF1',
        refund_type: :sale
    }
    assert refund = @gateway.refund(nil, response.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_capture_void_zi
    card = credit_card('4358525174655353',
                       {:brand => '',
                        :verification_value => '123',
                        :month => 12,
                        :year => 2015,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BEC'
    }
    auth = @gateway.authorize(10000, card, options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BED'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BF3',
        refund_type: :capture
    }
    assert refund = @gateway.refund(nil, capture.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_create_token
    card = credit_card('4929600002000005',
                       {:brand => '',
                        :verification_value => '555',
                        :month => 6,
                        :year => 2018,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BE6'
    }
    response = @gateway.store(card, options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_use_token_sale
    card = credit_card('4929600002000005',
                       {:brand => '',
                        :verification_value => '555',
                        :month => 6,
                        :year => 2018,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BE6'
    }
    store = @gateway.store(card, options)
    assert_success store
    assert_equal 'Transaction+has+been+executed+successfully.', store.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        d2: '1694BE7'
    }
    response = @gateway.purchase(@amount, store.authorization[:token], options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
  end

  def test_use_token_auth_and_capture
    card = credit_card('4929600002000005',
                       {:brand => '',
                        :verification_value => '555',
                        :month => 6,
                        :year => 2018,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BE6'
    }
    store = @gateway.store(card, options)
    assert_success store
    assert_equal 'Transaction+has+been+executed+successfully.', store.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        d2: '1694BE8'
    }
    auth = @gateway.authorize(2000, store.authorization[:token], options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BE9'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message

  end

  def test_use_token_auth_and_void
    card = credit_card('4929600002000005',
                       {:brand => '',
                        :verification_value => '555',
                        :month => 6,
                        :year => 2018,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BE6'
    }
    store = @gateway.store(card, options)
    assert_success store
    assert_equal 'Transaction+has+been+executed+successfully.', store.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        d2: '1694BE8'
    }
    auth = @gateway.authorize(2000, store.authorization[:token], options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message

    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BEA'
    }
    assert void = @gateway.void(auth.authorization, options)
    assert_success void
    assert_equal 'Transaction+has+been+executed+successfully.', void.message

  end

  def test_token_referral_credit
    card = credit_card('4929600002000005',
                       {:brand => '',
                        :verification_value => '555',
                        :month => 6,
                        :year => 2018,
                        :first_name => 'John',
                        :last_name => 'Tailor',
                       })
    options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        email: 'j.tailor@test.com',
        d2: '1694BE6'
    }
    store = @gateway.store(card, options)
    assert_success store
    assert_equal 'Transaction+has+been+executed+successfully.', store.message
        options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123',
        ip: '1.1.1.1',
        d2: '1694BE8'
    }
    auth = @gateway.authorize(2000, store.authorization[:token], options)
    assert_success auth
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message
        options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        ip: '1.1.1.1',
        d2: '1694BE9'
    }
    assert capture = @gateway.capture(nil, auth.authorization, options)
    assert_success capture
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message

    options = {
       order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
       ip: '1.1.1.1',
       d2: '16D23D3',
       refund_type: :post_clearing_credit
    }
    assert refund = @gateway.refund(nil, capture.authorization, options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

end
