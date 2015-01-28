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

    @amount = 10000
    # TODO Why does this fail, this should be a CVV2 checked card
    # @credit_card = credit_card('4123450131003312',
    #                            {:brand => 'visa',
    #                             :verification_value => '815',
    #                             :month => 3,
    #                             :year => (Time.now.year + 1),
    #                            })

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

    # TODO
    @billing_address = {
        company:  'Widgets Inc',
        city:     'Tokyo',
        state:    '13', # TOKYO - http://www.unece.org/fileadmin/DAM/cefact/locode/Subdivision/jpSub.htm
        zip:      '163-6038',
        country:  'JP'
    }

    @options = {
        order_id: Time.now.getutc.strftime("%Y%m%d%H%M%S%L"),
        description: 'dummy'
    }
  end

  def test_successful_store
    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        customer: stamp,
    }
    response = @gateway.store(@credit_card, @options)
    assert_success response
    assert_equal '正常', response.message
    assert_equal '2S63046', response.authorization[:card_aquirer_code]

  end

  def test_failure_store
    stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        customer: stamp,
    }
    response = @gateway.store(@declined_card_c1430, @options)
    assert_failure response
    assert_equal 'C1430', response.params['infocode']
    assert_equal '-7', response.params['status']
    assert_equal 'カード与信失敗(02-00)', response.message
  end

  def test_successful_purchase
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, @options)
    assert_success response

    order = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        order_id: order,
    }
    response = @gateway.purchase(@amount, cust, @options)
    assert_success response
    assert_equal '正常', response.message
  end

  def test_failed_purchase_invalid_member
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, @options)
    assert_success response

    order = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        order_id: order,
    }
    response = @gateway.purchase(@amount, '111', @options)
    assert_failure response
    assert_equal 'C2101', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal '会員登録なし', response.message
  end


  def test_successful_authorize_and_capture
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, @options)
    assert_success response

    order = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        order_id: order,
    }
    auth = @gateway.authorize(@amount, cust, @options)
    assert_success auth
    assert_equal '正常', auth.message

    @options = {
        order_id: order,
        customer: cust
    }
    assert capture = @gateway.capture(@amount, auth.authorization, @options)
    assert_success capture
    assert_equal '正常', capture.message
  end

  def test_failed_authorize_invalid_member
    cust = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        customer: cust,
    }
    response = @gateway.store(@credit_card, @options)
    assert_success response

    order = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
    @options = {
        order_id: order,
    }
    response = @gateway.authorize(@amount, '111', @options)
    assert_failure response
    assert_equal 'C2101', response.params['infocode']
    assert_equal '-2', response.params['status']
    assert_equal '会員登録なし', response.message
  end

  # def test_partial_capture
  #   auth = @gateway.authorize(@amount, @credit_card, @options)
  #   assert_success auth
  #
  #   assert capture = @gateway.capture(@amount-1, auth.authorization)
  #   assert_success capture
  # end
  #
  # def test_failed_capture
  #   stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
  #   @options = {
  #       order_id: stamp,
  #   }
  #   response = @gateway.capture(@amount, nil, @options)
  #   assert_failure response
  # end
  #
  # def test_successful_refund
  #   stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
  #   @options = {
  #       order_id: stamp,
  #       description: "#{stamp}Sale"
  #   }
  #   purchase = @gateway.purchase(@amount, @credit_card, @options)
  #   assert_success purchase
  #
  #   @options = {
  #       order_id: stamp
  #   }
  #   assert refund = @gateway.refund(nil, purchase.authorization, @options)
  #   assert_success refund
  # end

  # def test_partial_refund
  #   purchase = @gateway.purchase(@amount, @credit_card, @options)
  #   assert_success purchase
  #
  #   assert refund = @gateway.refund(@amount-1, purchase.authorization)
  #   assert_success refund
  # end
  #
  # def test_failed_refund
  #   response = @gateway.refund(nil, '')
  #   assert_failure response
  # end
  #
  # def test_successful_void
  #   stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
  #   @options = {
  #       order_id: stamp,
  #       description: "#{stamp}Auth"
  #   }
  #   auth = @gateway.authorize(@amount, @credit_card, @options)
  #   assert_success auth
  #
  #   @options = {
  #       order_id: stamp
  #   }
  #   assert void = @gateway.void(auth.authorization, @options)
  #   assert_success void
  # end
  #
  # def test_failed_void
  #   stamp = Time.now.getutc.strftime("%Y%m%d%H%M%S%L")
  #   @options = {
  #       order_id: stamp
  #   }
  #   response = @gateway.void('', @options)
  #   assert_failure response
  # end

end
