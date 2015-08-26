require 'test_helper'

# == Description
# Credorax supports both Credit Card based operations, and those where a token is provided
# which represents Credit Card details previously stored with Credorax
#
# This test class will test the options were CREDIT CARD details are supplied.
#
class CredoraxTest < Test::Unit::TestCase

  MERCHANT_ID = 'CRED001'
  MD5_CIPHER_KEY = 'AAAA1AAA'
  NAME_ON_STATEMENT = 'COMPANY X'

  CARD_NUMBER = '4037660000001115'
  CARD_NUMBER_MASKED = '4...1115'

  RESPONSE_ID = '1A1406236'

  TRANSACTION_ID = '502201062691'

  AUTHORIZATION_CODE = '102479'

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
        description: 'Store Item123' # Limited to 13 characters
    }

  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    @options[:email] = 'noone@example.com'

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    expected = {
        :authorization_code=>AUTHORIZATION_CODE,
        :response_id=>RESPONSE_ID,
        :transaction_id=>TRANSACTION_ID,
        :previous_request_id=>@order_id,
        :response_reason_code=>"00"
    }
    assert_equal expected, response.authorization
    assert_equal 'Transaction+has+been+executed+successfully.', response.message
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_9_card_not_identified)

    @options[:email] = 'noone@example.com'
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], response.error_code
    assert_equal 'Card+cannot+be+identified (-9)', response.message
  end

  def test_failed_purchase_bad_description
    @options[:email] = 'noone@example.com'
    @options[:description] = 'Store Item1234'
    assert_raise(ArgumentError){ @gateway.purchase(@amount, @credit_card, @options) }
  end

  def test_failed_purchase_bad_dba
    @options[:email] = 'noone@example.com'
    @options[:merchant] = '12345678901234567890123456'
    assert_raise(ArgumentError){ @gateway.purchase(@amount, @credit_card, @options) }
  end

  def test_failed_purchase_bad_card_name
    @gateway.options[:cardholder_name_padding] = false
    @options[:email] = 'noone@example.com'
    credit_card = credit_card(CARD_NUMBER,
                               {:brand => nil,
                                :verification_value => '123',
                                :month => 3,
                                :year => (Time.now.year + 1),
                                :first_name => 'L',
                                :last_name => 'L',
                               })
    assert_raise(ArgumentError){ @gateway.purchase(@amount, credit_card, @options) }
  end

  def test_successful_authorize_and_capture
    @gateway.expects(:ssl_post).times(2).returns(
        successful_authorize_response
    ).then.returns(
        successful_capture_response
    )

    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    expected = {
        :authorization_code=>AUTHORIZATION_CODE,
        :response_id=>RESPONSE_ID,
        :transaction_id=>TRANSACTION_ID,
        :previous_request_id=>@order_id,
        :response_reason_code=>"00"
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
        :response_reason_code=>"00"
    }
    assert_equal expected, capture.authorization
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
    assert capture.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_9_card_not_identified)

    @options[:email] = 'noone@example.com'
    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], response.error_code
    assert_equal 'Card+cannot+be+identified (-9)', response.message
  end

  def test_partial_capture
    @gateway.expects(:ssl_post).times(2).returns(
        successful_authorize_response
    ).then.returns(
        successful_partial_capture_response
    )

    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

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
        :response_reason_code=>"00"
    }
    assert_equal expected, capture.authorization
    assert_equal 'Transaction+has+been+executed+successfully.', capture.message
    assert capture.test?
  end

  def test_failed_capture_malformed_parameter
    @gateway.expects(:ssl_post).times(2).returns(
        successful_authorize_response
    ).then.returns(
        failed_capture_response_malformed_parameter
    )

    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
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

  def test_failed_capture_bad_reference
    @gateway.expects(:ssl_post).times(2).returns(
        successful_authorize_response
    ).then.returns(
        failed_capture_response_bad_reference
    )

    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    @bad_auth = {
        authorization_code: auth.authorization[:authorization_code],
        response_id: auth.authorization[:response_id],
        transaction_id: auth.authorization[:transaction_id],
        token: auth.authorization[:token],
        previous_request_id: '1'
    }
    assert capture = @gateway.capture(nil, @bad_auth, @options)
    assert_failure capture
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], capture.error_code
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Successful+referred+transaction+%5B1%2F1A1406251%5D+has+not+been+found. (-9)', capture.message
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).times(2).returns(
        successful_purchase_response
    ).then.returns(
        successful_refund_response
    )

    @options[:email] = 'noone@example.com'
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
        refund_type: :sale
    }
    assert refund = @gateway.refund(nil, purchase.authorization, @options)
    assert_success refund
    assert_equal 'Transaction+has+been+executed+successfully.', refund.message
    assert refund.test?
  end

  def test_failed_refund_malformed_parameter
    @gateway.expects(:ssl_post).times(2).returns(
        successful_purchase_response
    ).then.returns(
        failed_refund_response_malformed_parameter
    )

    @options[:email] = 'noone@example.com'
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

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
    response = @gateway.refund(nil, @bad_auth, @options)
    assert_failure response
    assert_equal CredoraxGateway::RESULT_CODES[:parameter_malformed], response.error_code
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty. (-9)', response.message
  end

  def test_successful_void
    @gateway.expects(:ssl_post).times(2).returns(
        successful_authorize_response
    ).then.returns(
        successful_void_response
    )

    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S"),
    }
    assert void = @gateway.void(auth.authorization, @options)
    assert_success void
    assert_equal 'Transaction+has+been+executed+successfully.', void.message
    assert void.test?
  end

  def test_failed_void
    @gateway.expects(:ssl_post).times(2).returns(
        successful_authorize_response
    ).then.returns(
        failed_void_response
    )

    @options[:email] = 'noone@example.com'
    auth = @gateway.authorize(@amount, @credit_card, @options)
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
    assert void = @gateway.void(@bad_auth, @options)
    assert_failure void
    assert_equal '2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty. (-9,09)', void.message
    assert void.test?
  end

  def test_failed_verify
    assert_raise(NotImplementedError){ @gateway.verify(@credit_card, @options) }
  end

  private

  def successful_purchase_response
    "M=#{MERCHANT_ID}&O=1&T=01%2F22%2F2015+01%3A13%3A40&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&b2=1&z1=#{RESPONSE_ID}&z13=#{TRANSACTION_ID}&z14=N&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=7ac3f12d3bd73898715b48d66b4bb432"
  end

  def failed_9_card_not_identified
    "z2=-9&z3=Card+cannot+be+identified&T=01%2F22%2F2015+01%3A48%3A08"
  end

  def successful_authorize_response
    "M=#{MERCHANT_ID}&O=2&T=01%2F22%2F2015+02%3A28%3A51&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&b2=1&z1=#{RESPONSE_ID}&z13=#{TRANSACTION_ID}&z14=N&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}=0&z6=00&z9=-&K=30ed6b9dbb12a388f1aab03e150adb7e"
  end

  def successful_capture_response
    "M=#{MERCHANT_ID}&O=3&T=01%2F22%2F2015+02%3A28%3A53&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&z1=#{RESPONSE_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=0&z5=0&z6=00&K=c24c3fc4fb78cee7f9a7b356233bf777"
  end

  def successful_partial_capture_response
    "M=#{MERCHANT_ID}&O=3&T=01%2F22%2F2015+02%3A54%3A00&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{(@amount_as_euros-10).to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&z1=#{RESPONSE_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=0&z5=0&z6=00&K=c27391540a3d7fa092a90f72f6e0accb"
  end

  def failed_capture_response_malformed_parameter
    "M=#{MERCHANT_ID}&O=3&T=01%2F22%2F2015+03%3A01%3A54&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=EUR&b1=-&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty.&K=456e625fd9c84d3230cc26c7c5a106e1"
  end

  def failed_capture_response_bad_reference
    "M=#{MERCHANT_ID}&O=3&T=01%2F22%2F2015+03%3A05%3A34&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=EUR&b1=-&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Successful+referred+transaction+%5B1%2F1A1406251%5D+has+not+been+found.&K=6fcee268e9789d7028ac3b49b57628fe"
  end

  def successful_refund_response
    "M=#{MERCHANT_ID}&O=9&T=01%2F22%2F2015+03%3A15%3A06&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&z1=#{RESPONSE_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=3f1db9e18db0a5e3397c84bb3d5c0291"
  end

  def failed_refund_response_malformed_parameter
    "M=#{MERCHANT_ID}&O=9&T=01%2F22%2F2015+03%3A22%3A41&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=-&b1=-&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty.&K=281eb6e9d0ce877085035a1b3b0bb2bd"
  end

  def successful_void_response
    "M=#{MERCHANT_ID}&O=4&T=01%2F22%2F2015+03%3A41%3A08&V=413&a1=#{@options[:order_id]}&a2=2&a4=#{@amount_as_euros.to_s}&a5=EUR&b1=#{CARD_NUMBER_MASKED}&z1=#{RESPONSE_ID}&z2=0&z3=Transaction+has+been+executed+successfully.&z4=#{AUTHORIZATION_CODE}&z5=0&z6=00&z9=-&K=dcc2bd3c3e3389838ed6c81d4faa41a3"
  end

  def failed_void_response
    "M=#{MERCHANT_ID}&O=4&T=01%2F22%2F2015+03%3A49%3A10&V=413&a1=#{@options[:order_id]}&a2=2&a4=-&a5=-&b1=-&z1=1A-1&z2=-9&z3=2.+At+least+one+of+input+parameters+is+malformed.%3A+Parameter+%5Bg4%5D+cannot+be+empty.&z6=09&K=cf1d2698dc1e96f73285327c28457aaf"
  end
end
