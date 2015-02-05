require 'test_helper'

class EcontextTest < Test::Unit::TestCase

  SHOP_ID       = 'A00000'
  CHECK_CODE    = 'A00001112233'
  LIVE_URL      = 'https://example.com/rcv_odr.aspx'


  def setup

    @gateway = EcontextGateway.new(
        shop_id: SHOP_ID,
        chk_code: CHECK_CODE,
        live_url: LIVE_URL
    )

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
        description: 'dummy'
    }
  end

  def test_failure_store
    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        customer: stamp,
    }
    assert_raise(ArgumentError){  @gateway.store('111111', options) }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: stamp,
        description: "#{stamp}Sale"
    }
    response = @gateway.purchase(@amount, @credit_card, options)
    assert_success response
    assert_equal '正常', response.message
  end

  def test_failed_purchase_c1430
    @gateway.expects(:ssl_post).returns(failed_c1430_purchase_response)

    response = @gateway.purchase(@amount, @declined_card_c1430, @options)
    assert_failure response
    assert_equal 'C1430', response.params['infocode']
    assert_equal '-7', response.params['status']
    assert_equal 'カード与信失敗(02-00)', response.message
  end

  def test_failed_purchase_c1483
    @gateway.expects(:ssl_post).returns(failed_c1483_purchase_response)

    response = @gateway.purchase(@amount, @declined_card_c1483, @options)
    assert_failure response
    assert_equal 'C1483', response.params['infocode']
    assert_equal '-7', response.params['status']
    assert_equal 'カード与信失敗(01-04)', response.message
  end

  def test_successful_authorize_and_capture
    @gateway.expects(:ssl_post).times(2).returns(
      successful_authorize_response
    ).then.returns(
      successful_capture_response
    )

    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: stamp,
        description: "#{stamp}Auth"
    }
    auth = @gateway.authorize(@amount, @credit_card, options)
    assert_success auth
    assert_equal '正常', auth.message

    options = {
        order_id: stamp
    }
    assert capture = @gateway.capture(@amount, auth.authorization, options)
    assert_success capture
    assert_equal '正常', capture.message
  end

  def test_failed_authorize_c1430
    @gateway.expects(:ssl_post).returns(failed_c1430_authorize_response)

    response = @gateway.authorize(@amount, @declined_card_c1430, @options)
    assert_failure response
    assert_equal 'C1430', response.params['infocode']
    assert_equal '-7', response.params['status']
    assert_equal 'カード与信失敗(02-00)', response.message
  end

  def test_partial_capture
    # NOT SUPPORTED BY ECONTEXT
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: stamp,
    }
    response = @gateway.capture(@amount, nil, options)
    assert_failure response
  end

  def test_successful_refund_from_a_purchase
    @gateway.expects(:ssl_post).times(2).returns(
        successful_purchase_response
    ).then.returns(
        successful_refund_response
    )

    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: stamp,
        description: "#{stamp}Sale"
    }
    purchase = @gateway.purchase(@amount, @credit_card, options)
    assert_success purchase

    assert refund = @gateway.refund(nil, purchase.authorization)
    assert_success refund
  end

  def test_successful_refund_from_a_auth_capture
    @gateway.expects(:ssl_post).times(3).returns(
        successful_authorize_response
    ).then.returns(
        successful_capture_response
    ).then.returns(
        successful_refund_response
    )

    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: stamp,
        description: "#{stamp}Auth"
    }
    auth = @gateway.authorize(@amount, @credit_card, options)
    assert_success auth

    options = {
        order_id: stamp
    }
    assert capture = @gateway.capture(@amount, auth.authorization, options)
    assert_success capture

    assert refund = @gateway.refund(nil, capture.authorization)
    assert_success refund
  end


  def test_partial_refund
    @gateway.expects(:ssl_post).times(2).returns(
        successful_purchase_response
    ).then.returns(
        successful_refund_response
    )

    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: stamp,
        description: "#{stamp}Sale"
    }
    purchase = @gateway.purchase(@amount, @credit_card, options)
    assert_success purchase

    # Send new amount, not the amount to refund (refund 6000 back to cardholder)
    assert refund = @gateway.refund(4000, purchase.authorization)
    assert_success refund
  end

  def test_failed_refund
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    bad_auth = {
        ecn_token: '',
        user_token: '',
        previous_order_id: '111',
        previous_paymt_code: 'C10',
        card_aquirer_code: '',
    }
    response = @gateway.refund(nil, bad_auth)
    assert_failure response
    assert_equal 'E1010', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal 'パラメータチェックエラー「orderID:111」', response.message
  end

  def test_successful_void
    @gateway.expects(:ssl_post).times(2).returns(
        successful_authorize_response
    ).then.returns(
        successful_void_response
    )

    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    options = {
        order_id: stamp,
        description: "#{stamp}Auth"
    }
    auth = @gateway.authorize(@amount, @credit_card, options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal '00異常なし', void.message
  end

  def test_failed_void
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    bad_auth = {
        ecn_token: '',
        user_token: '',
        previous_order_id: '111',
        previous_paymt_code: 'C10',
        card_aquirer_code: '',
    }
    response = @gateway.void(bad_auth)
    assert_failure response
  end

  def test_successful_verify
    assert_raise(NotImplementedError){ @gateway.verify(@credit_card, @options) }
  end

  private

  def successful_purchase_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4>1111</econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD>2S63046</shimukeCD><shoninCD>111111</shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_c1430_purchase_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-7</status><info>カード与信失敗(02-00)</info><infoCode>C1430</infoCode></result>".encode('Shift_JIS')
  end

  def failed_c1483_purchase_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-7</status><info>カード与信失敗(01-04)</info><infoCode>C1483</infoCode></result>".encode('Shift_JIS')
  end

  def successful_authorize_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econNo>9999999</econNo><econCardno4>1111</econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD>2S63046</shimukeCD><shoninCD>111111</shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_c1430_authorize_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-7</status><info>カード与信失敗(02-00)</info><infoCode>C1430</infoCode></result>".encode('Shift_JIS')
  end

  def successful_capture_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econCardno4></econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD></shimukeCD><shoninCD></shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_capture_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>正常</info><infoCode>E1099</infoCode></result>".encode('Shift_JIS')
  end

  def successful_refund_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>正常</info><infoCode>00000</infoCode><econCardno4></econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD></shimukeCD><shoninCD></shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_refund_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>パラメータチェックエラー「orderID:111」</info><infoCode>E1010</infoCode></result>".encode('Shift_JIS')
  end

  def successful_void_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>1</status><info>00異常なし</info><infoCode>00000</infoCode><econCardno4></econCardno4><cardExpdate></cardExpdate><cduserID></cduserID><shimukeCD></shimukeCD><shoninCD></shoninCD><ecnToken></ecnToken><cardentryURL></cardentryURL><paymentURL></paymentURL><directpayURL></directpayURL></result>".encode('Shift_JIS')
  end

  def failed_void_response
    "<?xml version=\"1.0\" encoding=\"shift_jis\"?><result><status>-2</status><info>パラメータチェックエラー「orderID:111」</info><infoCode>E1010</infoCode></result>".encode('Shift_JIS')
  end
end
