require 'test_helper'

# == Description
# ECONTEXT supports both Credit Card based operations, and those where a token is provided
# which represents Credit Card details previously stored with ECONTEXT
#
# This test class will test the options where tokens details are created and then supplied.
#
class EcontextCardMembersTest < Test::Unit::TestCase

  SHOP_ID       = 'A00000'
  CHECK_CODE    = 'A00001112233'
  LIVE_URL      = 'https://example.com/rcv_odr.aspx'


  def setup

    @gateway = EcontextGateway.new(
        shop_id: SHOP_ID,
        chk_code: CHECK_CODE,
        live_url: LIVE_URL
    )

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

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S%L"),
        session_id: Time.now.getutc.strftime("%Y%m%d%H%M%S%L"),
        description: 'dummy'
    }
  end

  def test_successful_store
    @gateway.expects(:ssl_post).returns(successful_store_response)
    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: stamp,
    }
    response = @gateway.store(@credit_card, options)
    assert_success response
    assert_equal '正常(00000)', response.message
    assert_equal '2S63046', response.authorization[:card_aquirer_code]

  end

  def test_failure_store
    @gateway.expects(:ssl_post).returns(failed_store_response)
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
    @gateway.expects(:ssl_post).times(2).returns(
        successful_store_response
    ).then.returns(
        successful_purchase_response
    )

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
    @gateway.expects(:ssl_post).times(2).returns(
        successful_store_response
    ).then.returns(
        failed_c2101_purchase_response
    )

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
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        successful_capture_response
    )

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
    assert_equal '正常(00000)', auth.message

    options = {
        customer: cust
    }
    assert capture = @gateway.capture(@amount, auth.authorization, options)
    assert_success capture
    assert_equal '正常', capture.message
  end

  def test_failed_authorize_invalid_member
    @gateway.expects(:ssl_post).times(2).returns(
        successful_store_response
    ).then.returns(
        failed_c2101_authorize_response
    )

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
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        failed_capture_response
    )

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
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_purchase_response
    ).then.returns(
        successful_refund_response
    )

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
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_purchase_response
    ).then.returns(
        successful_refund_response
    )

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
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_purchase_response
    ).then.returns(
        failed_refund_response
    )

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
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        successful_void_response
    )

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
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        failed_void_response
    )

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

  private

  def successful_store_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4></econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD>2S63046</shimukeCD><shoninCD></shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_store_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-7</status><info>カード与信失敗(02-00)</info><infoCode>C1430</infoCode></result>".encode('Shift_JIS')
  end

  def successful_purchase_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4>1111</econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD>2S63046</shimukeCD><shoninCD>111111</shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_c2101_purchase_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>会員登録なし</info><infoCode>C2101</infoCode></result>".encode('Shift_JIS')
  end


  def successful_authorize_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4>1111</econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD>2S63046</shimukeCD><shoninCD>111111</shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_c2101_authorize_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>会員登録なし</info><infoCode>C2101</infoCode></result>".encode('Shift_JIS')
  end

  def successful_capture_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4></econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD></shimukeCD><shoninCD></shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_capture_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>パラメータチェックエラー「orderID:111」</info><infoCode>E1010</infoCode></result>".encode('Shift_JIS')
  end

  def successful_refund_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4></econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD></shimukeCD><shoninCD></shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_refund_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>パラメータチェックエラー「orderID:111」</info><infoCode>E1010</infoCode></result>".encode('Shift_JIS')
  end

  def successful_void_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4></econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD></shimukeCD><shoninCD></shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_void_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>パラメータチェックエラー「orderID:111」</info><infoCode>E1010</infoCode></result>".encode('Shift_JIS')
  end
end
