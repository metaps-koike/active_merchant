require 'test_helper'

# == Description
# ECONTEXT supports both Credit Card based operations, and those where a token is provided
# which represents Credit Card details previously stored with ECONTEXT
#
# This test class will test the options where tokens details are created and then supplied.
#
class RemoteEcontextCardMembersTest < Test::Unit::TestCase
  def setup
    @gateway = EcontextGateway.new(fixtures(:econtext))

    # When connecting to Yen Merchant this is 10000 Yen
    # When connecting to USD Merchant this is 100.00 Dollars
    @amount = 10000

    @credit_card = credit_card('4980111111111111',
                               {:brand => 'visa',
                                :verification_value => '815',
                                :month => 3,
                                :year => (Time.now.year + 1),
                               })

    @declined_card_c1430 = credit_card('4980111111111112',
                                       {:brand => 'visa',
                                        :verification_value => '815',
                                        :month => 3,
                                        :year => (Time.now.year + 1),
                                       })
    @declined_card_c1483 = credit_card('4980111111111113',
                                       {:brand => 'visa',
                                        :verification_value => '815',
                                        :month => 3,
                                        :year => (Time.now.year + 1),
                                       })

  end

  def test_successful_store
    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: stamp,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response
    assert_equal '正常(00000)', response.message
    assert_equal '2S63046', response.authorization[:card_aquirer_code]

  end

  def test_successful_store_099_cvv
    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: stamp,
    }
    alt_credit_card = credit_card('4980111111111111',
                               {:brand => 'visa',
                                :verification_value => '099',
                                :month => 3,
                                :year => (Time.now.year + 1),
                               })
    response = @gateway.store(alt_credit_card, options)
    assert_success response
    assert_equal '正常(00000)', response.message
    assert_equal '2S63046', response.authorization[:card_aquirer_code]

  end

  def test_failure_store
    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: stamp,
    }
    response = @gateway.store(@declined_card_c1430, options)
    assert_failure response
    assert_equal 'C1430', response.params['infocode']
    assert_equal '-7', response.params['status']
    assert_equal 'カード与信失敗(02-00)(C1430)', response.message
  end

  def test_successful_purchase
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    response = @gateway.purchase(@amount, cust, options)
    assert_success response
    assert_equal '正常(00000)', response.message
  end

  def test_failed_purchase_invalid_member
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    response = @gateway.purchase(@amount, '111', options)
    assert_failure response
    assert_equal 'C2101', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal '会員登録なし(C2101)', response.message
  end

  def test_successful_authorize_and_capture
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    options = {
        order_id: Time.now.getutc.strftime("%L%S%M%H%d%m%Y"),
        session_id: Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    }
    auth = @gateway.authorize(@amount, cust, options)
    assert_success auth
    assert_equal '正常(00000)', auth.message

    options = {
        customer: cust
    }
    assert capture = @gateway.capture(@amount, auth.authorization, options)
    assert_success capture
    assert_equal '正常(00000)', capture.message
  end

  def test_successful_authorize_and_capture_custom_shipdate
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    options = {
        order_id: Time.now.getutc.strftime("%L%S%M%H%d%m%Y"),
        session_id: Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    }
    auth = @gateway.authorize(@amount, cust, options)
    assert_success auth
    assert_equal '正常(00000)', auth.message

    options = {
        customer: cust,
        ship_date: Time.now.getutc
    }
    assert capture = @gateway.capture(@amount, auth.authorization, options)
    assert_success capture
    assert_equal '正常(00000)', capture.message
  end

  def test_failed_authorize_invalid_member
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        order_id: order,
        session_id: session,
    }
    response = @gateway.authorize(@amount, '111', @options)
    assert_failure response
    assert_equal 'C2101', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal '会員登録なし(C2101)', response.message
  end

  def test_partial_capture
    # NOT SUPPORTED
  end

  def test_failed_capture
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    auth = @gateway.authorize(@amount, cust, options)
    assert_success auth

    options = {
        customer: '111'
    }
    bad_auth = {
        ecn_token: auth.authorization[:ecn_token],
        user_token: auth.authorization[:user_token],
        previous_order_id: '111',
        previous_paymt_code: auth.authorization[:previous_paymt_code],
        card_aquirer_code: auth.authorization[:card_aquirer_code],
    }
    assert response = @gateway.capture(@amount, bad_auth, options)
    assert_failure response
    assert_equal 'E1010', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal 'パラメータチェックエラー「orderID:111」(E1010)', response.message
  end

  def test_successful_refund
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    purchase = @gateway.purchase(@amount, cust, options)
    assert_success purchase

    assert refund = @gateway.refund(nil, purchase.authorization)
    assert_success refund
  end

  def test_partial_refund
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    purchase = @gateway.purchase(@amount, cust, options)
    assert_success purchase

    # Send new amount, not the amount to refund (refund 6000 back to cardholder)
    assert refund = @gateway.refund(4000, purchase.authorization)
    assert_success refund
  end

  def test_failed_refund
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    purchase = @gateway.purchase(@amount, cust, options)
    assert_success purchase

    bad_auth = {
        ecn_token: purchase.authorization[:ecn_token],
        user_token: purchase.authorization[:user_token],
        previous_order_id: '111',
        previous_paymt_code: purchase.authorization[:previous_paymt_code],
        card_aquirer_code: purchase.authorization[:card_aquirer_code],
    }
    response = @gateway.refund(nil, bad_auth)
    assert_failure response
    assert_equal 'E1010', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal 'パラメータチェックエラー「orderID:111」(E1010)', response.message
  end

  def test_successful_void
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    auth = @gateway.authorize(@amount, cust, options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
  end

  def test_failed_void
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response

    order = Time.now.getutc.strftime("%L%S%M%H%d%m%Y")
    session = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: order,
        session_id: session,
    }
    auth = @gateway.authorize(@amount, cust, options)
    assert_success auth

    bad_auth = {
        ecn_token: auth.authorization[:ecn_token],
        user_token: auth.authorization[:user_token],
        previous_order_id: '111',
        previous_paymt_code: auth.authorization[:previous_paymt_code],
        card_aquirer_code: auth.authorization[:card_aquirer_code],
    }
    response = @gateway.void(bad_auth)
    assert_failure response
    assert_equal 'E1010', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal 'パラメータチェックエラー「orderID:111」(E1010)', response.message
  end

end
