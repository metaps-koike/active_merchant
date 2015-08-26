require 'test_helper'


# == Description
# Credorax supports both Credit Card based operations, and those where a token is provided
# which represents Credit Card details previously stored with Credorax
#
# This test class will test the options were tokens are used. Credit Card details will only be supplied
# in the initial calls to generate the token.
#
class CredoraxTokenVariantTest < Test::Unit::TestCase

  MERCHANT_ID = 'CRED001'
  MD5_CIPHER_KEY = 'AAAA1AAA'
  NAME_ON_STATEMENT = 'COMPANY X'

  CARD_NUMBER = '4037660000001115'
  CARD_NUMBER_MASKED = '4...1115'

  RESPONSE_ID = '1A1406236'

  TRANSACTION_ID = '502201062691'

  AUTHORIZATION_CODE = '102479'

  TOKEN = '1A011FFFFFFFDFB4'
  BAD_TOKEN = '111'

  def setup

    @gateway = CredoraxGateway.new(
        merchant_id: MERCHANT_ID,
        md5_cipher_key: MD5_CIPHER_KEY,
        name_on_statement: NAME_ON_STATEMENT
    )

    @credit_card = credit_card(CARD_NUMBER,
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
    @amount_as_euros = 100

    @billing_address = {
        company:  'Widgets Inc',
        city:     'Tokyo',
        state:    '13', # TOKYO - http://www.unece.org/fileadmin/DAM/cefact/locode/Subdivision/jpSub.htm
        zip:      '163-6038',
        country:  'JP'
    }

    @order_id = Time.now.getutc.strftime("%Y%m%d%H%M%S")

    @options = {
        order_id: @order_id,
        billing_address: @billing_address,
        description: 'Store Item123', # Limited to 13 characters
        invoice: 'merchant invoice'
    }

  end

  def test_successful_store
    @gateway.expects(:ssl_post).returns(successful_store_response)

    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = @amount
    response = @gateway.store(@credit_card, @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert_not_nil response.authorization[:token]
  end

  def test_failure_store
    @gateway.expects(:ssl_post).returns(failed_9_card_not_identified)

    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = @amount
    response = @gateway.store(@declined_card, @options)
    assert_failure response
    assert_equal 'Card+cannot+be+identified (-9)', response.message
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).times(2).returns(
        successful_store_response
    ).then.returns(
        successful_purchase_response
    )

    @options[:email] = 'noone@example.com'
    @options[:store_verification_amount] = @amount
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        email: 'noone@example.com',
        description: 'Store Item123', # Limited to 13 characters
    }

    response = @gateway.purchase(@amount, store.authorization[:token], @options)
    assert_success response
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).times(2).returns(
        successful_store_response
    ).then.returns(
        failed_purchase_response_invalid_token
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        email: 'noone@example.com',
        description: 'Store Item123', # Limited to 13 characters
    }

    response = @gateway.purchase(@amount, BAD_TOKEN, @options)
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], response.error_code
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Successful+referred+transaction+for+the+account+%5B111111111%5D+has+not+been+found. (-9)', response.message
  end

  def test_successful_authorize_and_capture
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        successful_capture_response
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], @options)
    assert_success auth
    expected = {
        :authorization_code=>AUTHORIZATION_CODE,
        :response_id=>RESPONSE_ID,
        :transaction_id=>TRANSACTION_ID,
        :previous_request_id=>@order_id,
        :response_reason_code=>"00",
        :token=>TOKEN
    }
    assert_equal expected, auth.authorization
    assert_equal 'Transaction+has+been+executed+successfully.', auth.message
    assert auth.test?

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    assert capture = @gateway.capture(nil, auth.authorization, @options)
    assert_success capture
    expected = {
        :authorization_code=>'0',
        :response_id=>RESPONSE_ID,
        :transaction_id=>nil,
        :previous_request_id=>@options[:order_id],
        :response_reason_code=>"00",
        :token=>TOKEN
    }
    assert_equal expected, capture.authorization
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
    assert capture.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_9_card_not_identified)

    @options[:email] = 'noone@example.com'
    response = @gateway.authorize(@amount, BAD_TOKEN, @options)
    assert_failure response
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], response.error_code
    assert_equal 'Card+cannot+be+identified (-9)', response.message
  end

  def test_partial_capture
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        successful_partial_capture_response
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    assert capture = @gateway.capture(@amount-1000, auth.authorization, @options)
    assert_success capture
    expected = {
        :authorization_code=>'0',
        :response_id=>RESPONSE_ID,
        :transaction_id=>nil,
        :previous_request_id=>@options[:order_id],
        :response_reason_code=>"00",
        :token=>TOKEN
    }
    assert_equal expected, capture.authorization
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
    assert capture.test?
  end

  def test_failed_capture_malformed_parameter
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        failed_capture_response_malformed_parameter
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], @options)
    assert_success auth

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    @bad_auth = {
        authorization_code: auth.authorization[:authorization_code],
        response_id: auth.authorization[:response_id],
        transaction_id: auth.authorization[:transaction_id],
        token: auth.authorization[:token],
        previous_request_id: ''
    }
    assert capture = @gateway.capture(nil, @bad_auth, @options)
    assert_failure capture
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], capture.error_code
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty. (-9)', capture.message
  end

  def test_failed_capture_bad_token
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        failed_capture_response_bad_token
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], @options)
    assert_success auth

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    @bad_auth = {
        authorization_code: auth.authorization[:authorization_code],
        response_id: auth.authorization[:response_id],
        transaction_id: auth.authorization[:transaction_id],
        token: BAD_TOKEN,
        previous_request_id: auth.authorization[:previous_request_id]
    }
    assert capture = @gateway.capture(nil, @bad_auth, @options)
    assert_failure capture
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], capture.error_code
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Successful+referred+transaction+for+the+account+%5B111%5D+has+not+been+found. (-9)', capture.message
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).times(4).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        successful_capture_response
    ).then.returns(
        successful_refund_response
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    capture = @gateway.capture(nil, auth.authorization, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        refund_type: :capture
    }
    assert refund = @gateway.refund(nil, capture.authorization, @options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_successful_refund_purchase
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_purchase_response
    ).then.returns(
        successful_refund_response
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123' # Limited to 13 characters
    }
    purchase = @gateway.purchase(@amount, store.authorization[:token], @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        refund_type: :sale
    }
    assert refund = @gateway.refund(nil, purchase.authorization, @options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
  end

  def test_failed_refund_malformed_parameter
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_purchase_response
    ).then.returns(
        failed_refund_response_malformed_parameter
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        description: 'Store Item123' # Limited to 13 characters
    }
    purchase = @gateway.purchase(@amount, store.authorization[:token], @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        refund_type: :sale
    }
    @bad_auth = {
        authorization_code: purchase.authorization[:authorization_code],
        response_id: purchase.authorization[:response_id],
        transaction_id: purchase.authorization[:transaction_id],
        token: purchase.authorization[:token],
        previous_request_id: ''
    }
    assert refund = @gateway.refund(nil, @bad_auth, @options)
    assert_failure refund
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], refund.error_code
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty. (-9)', refund.message
  end

  def test_successful_void
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        successful_void_response
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    assert void = @gateway.void(auth.authorization, @options)
    assert_success void
    assert_equal 'Transaction+has+been+executed+successfully.', void.message
  end

  def test_failed_void
    @gateway.expects(:ssl_post).times(3).returns(
        successful_store_response
    ).then.returns(
        successful_authorize_response
    ).then.returns(
        failed_void_response
    )

    @options[:email] = 'noone@example.com'
    store = @gateway.store(@credit_card, @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    auth = @gateway.authorize(@amount, store.authorization[:token], @options)

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    @bad_auth = {
        authorization_code: auth.authorization[:authorization_code],
        response_id: auth.authorization[:response_id],
        transaction_id: auth.authorization[:transaction_id],
        token: auth.authorization[:token],
        previous_request_id: ''
    }
    assert void = @gateway.void(@bad_auth, @options)
    assert_failure void
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty. (-9)', void.message
  end

  private

  def successful_store_response
    "M=#{MERCHANT_ID}&O=10&T=01%2F23%2F2015+06%3A05%3A17&V=413&a1=#{@options[:order_id]}&a2=2&a4=5&a5=EUR&b1=#{CARD_NUMBER_MASKED}&b2=1&g1=#{TOKEN}&z1=#{RESPONSE_ID}&z13=#{TRANSACTION_ID}&z14=P&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=b929f4405bdaabb8e32ef7ba7820039f"
  end

  def successful_purchase_response
    "M=#{MERCHANT_ID}&O=11&T=01%2F22%2F2015+06%3A26%3A51&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&g1=#{TOKEN}&z1=#{RESPONSE_ID}&z13=#{TRANSACTION_ID}&z14=N&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=72e5b00687ea278514885e9133c85323"
  end

  def failed_purchase_response_invalid_token
    "M=#{MERCHANT_ID}&O=11&T=01%2F22%2F2015+06%3A30%3A03&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=-&g1=#{BAD_TOKEN}&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Successful+referred+transaction+for+the+account+%5B111111111%5D+has+not+been+found.&K=ca0df902403cb81312ec6cc9cf1c5d03"
  end

  def failed_9_card_not_identified
    "z2=-9&z3=Card+cannot+be+identified&T=01%2F22%2F2015+05%3A39%3A18"
  end

  def successful_authorize_response
    "M=#{MERCHANT_ID}&O=28&T=01%2F22%2F2015+05%3A28%3A07&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&b2=1&g1=#{TOKEN}&z1=#{RESPONSE_ID}&z13=#{TRANSACTION_ID}&z14=N&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=a33d7f0d7948afbdeba7b38fc77a5930"
  end

  def successful_capture_response
    "M=#{MERCHANT_ID}&O=29&T=01%2F22%2F2015+05%3A28%3A09&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&g1=#{TOKEN}&z1=#{RESPONSE_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=0&z5=0&z6=00&K=8967be99a2d04c695fca8f74b9d48f5a"
  end

  def successful_partial_capture_response
    "M=#{MERCHANT_ID}&O=29&T=01%2F22%2F2015+05%3A50%3A38&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{(@amount_as_euros-10).to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&g1=#{TOKEN}&z1=#{RESPONSE_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=0&z5=0&z6=00&K=076591587ec8534e87aa9902072bed1d"
  end

  def failed_capture_response_malformed_parameter
    "M=#{MERCHANT_ID}&O=29&T=01%2F22%2F2015+06%3A00%3A11&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=EUR&b1=-&g1=g1=#{TOKEN}&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty.&K=b3500dfd918b636bf5d468f72ec82c33"
  end

  def failed_capture_response_bad_token
    "M=#{MERCHANT_ID}&O=29&T=01%2F22%2F2015+06%3A08%3A16&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=EUR&b1=-&g1=#{BAD_TOKEN}&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Successful+referred+transaction+for+the+account+%5B111%5D+has+not+been+found.&K=3a177642a88ef3aa1d8520fb85073f1f"
  end

  def successful_refund_response
    "M=#{MERCHANT_ID}&O=15&T=01%2F22%2F2015+06%3A43%3A19&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&g1=#{TOKEN}&z1=#{RESPONSE_ID}&z13=#{TRANSACTION_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=7f914baec6227e3093a3f8b7c5502e08"
  end

  def failed_refund_response_malformed_parameter
    "M=#{MERCHANT_ID}&O=15&T=01%2F22%2F2015+06%3A49%3A21&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=EUR&b1=-&g1=#{TOKEN}&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty.&K=81ab7e3a0d5ea0a14e7168ab7f959dce"
  end

  def successful_void_response
    "M=#{MERCHANT_ID}&O=14&T=01%2F22%2F2015+06%3A57%3A01&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&g1=#{TOKEN}&z1=#{RESPONSE_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=275fff5cb4419b4a18932fa6152c06a0"
  end

  def failed_void_response
    "M=#{MERCHANT_ID}&O=14&T=01%2F22%2F2015+07%3A01%3A29&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=EUR&b1=-&g1=#{TOKEN}&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty.&K=94b39be2233a367ebadb947e4df579fa"
  end
end
