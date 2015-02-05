require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:


    #
    # == Description
    # The EcontextGateway class supports interaction with {ECONTEXT's}[http://www.econtext.jp] Payment Gateway Service.
    # This ActiveMerchant Gateway class supports two forms of interaction with ECONTEXT.
    #
    # * Credit Card Payment - Non-membership :- Credit Card must be supplied in Purchase and Authorisation calls
    # * Credit Card Payment - Member Service :- Credit Card details are stored with ECONTEXT and referenced in future operations with a Card Token
    #
    # This gateway class uses the following ActiveMerchant method to ECONTEXT operation mapping
    # A mapping is defined by a combination of ```fncCode (f)``` and ```paymtCode (p)``` values in the request sent to ECONTEXT
    #
    # | ActiveMerchant  |  Non-membership  |  Member Service
    # | --------------- | ---------------- | --------------------------------
    # | purchase        |  p=c10/f=10      |  p=c20/f=10
    # | authorize       |  p=c10/f=8       |  p=c20/f=8
    # | capture         |  p=c10/f=12      |  p=c20/f=12
    # | void            |  p=c10/f=20      |  p=c20/f=20
    # | refund          |  p=c10/f=20      |  p=c20/f=20 (API mandates same paymtCode as used to create order) (May need to call f=19 to do partial refund)
    # | store           |  N/A             |  p=c20/f=01 (Create), p=c20/f=02 (Update)
    # | unstore         |  N/A             |  p=c20/f=03 (Only deletes card, not the userid)
    #
    #
    class EcontextGateway < Gateway

      PAYMENT_CODE = {
          cash:                    'A10',
          card_non_membership:     'C10',
          card_membership:         'C20'
      }

      FNC_CODES = {
        member_serv_register_card:              '01',
        member_serv_update_card:                '02',
        member_serv_delete_card:                '03',
        member_serv_card_refe:                  '04',
        card_register_and_auth:                 '08', # Need to capture after
        cash_card_reg_auth_sale:                '10', # Register by cash or card, then auth, then sales
        capture:                                '12', # Capture card and paypal settlement
        change_charge_amount:                   '19', # Change the charge amount of order by credit card
        cancel_order:                           '20',
        member_serv_register_and_auth:          '21',
        member_serv_register_auth_capture:      '22',
        register_card_and_auth:                 '23',
        register_card_and_auth_capture:         '24',
        reauth_old_transaction:                 '30'
      }

      STATUS = {
          success:                              '1',
          error_retry_possible:                 '-1',
          error_retry_impossible_request_fail:  '-2',
          error_retry_impossible_econ_fail:     '-3',
          authorization_error:                  '-7'
      }

      CARD_ACQUIRERS = {
        nicos:            '2s50001', # Mitsubishi UFJ NICOS (ニコス)
        smbc_cc:          '2a99663', # Sumitomo Mitsui Card Company
        nicos_ufj:        '2a99664', # Mitsubishi UFJ NICOS (UFJ)
        saison:           '2S10035', # Credit Saison
        nicos_dc:         '2a99662', # Mitsubishi UFJ NICOS (DC)
        uc:               '2a99665', # UC
        jcb:              '2a99661', #JCB
        amex:             '2a99819', # American Express
        aeon:             '2S63046', # AEON
        aplus:            '2s59681', # Aplus
        omc:              '2s63141', # OMC (Cedyna)
        toyota_finance:   '2s77334', # Toyota Finance
        central_finance:  '2s58588', # Central Finance (Cedyna)
        sumishin:         '2S49631', # Sumishin Life Card
        jaccs:            '2s59110', # JACCS
        life_Card:        '2959876', # Life Card
        diners:           '2a99660', # DINERS (Citi card Japan)
        rakuten:          '2S59875', # Rakuten Card
        orico:            '2s59880', # Orico
      }

      self.test_url = 'https://test.econ.ne.jp/odr/rcv/rcv_odr.aspx'
      #self.live_url = 'https://example.com/live' - NOT USED

      self.supported_countries = ['JP']
      self.default_currency = 'JPY'
      self.money_format = :dollars
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.ssl_version = :SSLv3

      self.homepage_url = 'http://www.econtext.jp' # Japanese Language
      self.display_name = 'ECONTEXT'

      STANDARD_ERROR_CODE_MAPPING = {}

      # Initialize the Gateway
      #
      # The gateway requires that valid data defined
      # in the +options+ hash.
      #
      # === Options
      #
      #  * <tt>:shop_id => +string+</tt> - This will be assigned to you from ECONTEXT. Known as the SITE CODE (サイトコード)
      #  * <tt>:chk_code => +string+</tt> - This will be assigned to you from ECONTEXT. Known as the SITE CHECK CODE (サイトチェックコード)
      #  * <tt>:live_url => +string+</tt> This will be assigned to you from ECONTEXT.
      #  * <tt>:test => +true+ or +false+</tt> - Force test transactions
      #
      # For example:
      # ```
      # @gateway = EcontextGateway.new(
      #     shop_id: 'AA00001',
      #     chk_code: 'A23SD5',
      #     live_url: 'https://test.econ.ne.jp/odr/rcv/rcv_odr.aspx' # <--This is the test url
      # )
      # ```
      #
      def initialize(options={})
        requires!(options, :shop_id, :chk_code, :live_url)
        super
      end

      # Perform a purchase.
      #
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === money
      #
      # Two exponents are implied, without a decimal, except for currencies with zero exponents (e.g. JPY).
      # For example, when paying 10.00 GBP, the value should be sent as 1000. When paying 10 JPY, the value should be sent as 10.
      #
      # === Options
      #
      #  * <tt>:order_id => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single shop_id
      #
      # ==== Basic
      #
      # To use this operation, +payment+ should be a ActiveMerchant::Billing::CreditCard instance.
      # Specify the:
      #  * number
      #  * month
      #  * year
      #  * verification_value
      #  * name
      #
      # Also, additional parameters need to be defined in options
      #  * <tt>:description => +string+</tt> The additional text that is shown on a cardholder's statement.
      #
      # ==== Card Membership
      #
      # To use this operation, +payment+ should be a +String+ representation of a ECONTEXT 'token' that is defined in the 'cduserID' parameter.
      # This token will have been created using the +store+ method.
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:ecn_token</tt>
      #  * <tt>:user_token</tt>
      #  * <tt>:card_aquirer_code</tt>
      #  * <tt>:previous_order_id</tt> - The order_id used in this operation
      #  * <tt>:previous_paymt_code</tt> - The +paymt_code+ used in this operation, distinquishes between basic 'C10' and card membership 'C20'
      #
      def purchase(money, payment, options={})
        purchase_or_auth(FNC_CODES[:cash_card_reg_auth_sale], money, payment, options)
      end

      # Perform an authorize.
      #
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === money
      #
      # Two exponents are implied, without a decimal, except for currencies with zero exponents (e.g. JPY).
      # For example, when paying 10.00 GBP, the value should be sent as 1000. When paying 10 JPY, the value should be sent as 10.
      #
      # === Options
      #
      #  * <tt>:order_id => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single shop_id
      #
      # ==== Basic
      #
      # To use this operation, +payment+ should be a ActiveMerchant::Billing::CreditCard instance.
      # Specify the:
      #  * number
      #  * month
      #  * year
      #  * verification_value
      #  * name
      #
      # Also, additional parameters need to be defined in options
      #  * <tt>:description => +string+</tt> The additional text that is shown on a cardholder's statement.
      #
      # ==== Card Membership
      #
      # To use this operation, +payment+ should be a +String+ representation of a ECONTEXT 'token' that is defined in the 'cduserID' parameter.
      # This token will have been created using the +store+ method.
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:ecn_token</tt>
      #  * <tt>:user_token</tt>
      #  * <tt>:card_aquirer_code</tt>
      #  * <tt>:previous_order_id</tt> - The order_id used in this operation
      #  * <tt>:previous_paymt_code</tt> - The +paymt_code+ used in this operation, distinquishes between basic 'C10' and card membership 'C20'
      #
      def authorize(money, payment, options={})
        purchase_or_auth(FNC_CODES[:card_register_and_auth], money, payment, options)
      end

      def capture(money, authorization, options={})
        pCode = ''
        if options.has_key?(:customer) && !options[:customer].nil?
          # Membership
          requires!(options, :order_id)
          pCode = PAYMENT_CODE[:card_membership]
          post = build_capture_post(pCode, FNC_CODES[:capture], money, options)
          post['cduserID'] = options[:customer] #single-byte alphanumeric within 36 characters
        else
          requires!(options, :order_id)
          # Non-membership
          pCode = PAYMENT_CODE[:card_non_membership]
          post = build_capture_post(pCode, FNC_CODES[:capture], money, options)
        end
        commit(post, pCode, options[:order_id])
      end

      def refund(money, authorization, options={})
        if money.nil?
          void(authorization, options)
        else
          # money is the new transaction charge, NOT the amount to refund
          requires!(authorization, :previous_paymt_code, :previous_order_id)
          post = {
              'paymtCode' => authorization[:previous_paymt_code],
              'fncCode' => FNC_CODES[:change_charge_amount],
              'orderID' => authorization[:previous_order_id], # 6-47 characters, unique per shop_id
              'ordAmount' => localized_amount(money, 'JPY').to_i.to_s, # 1-999999 single-byte characters
          }
          commit(post, authorization[:previous_paymt_code], authorization[:previous_order_id])
        end
      end

      def void(authorization, options={})
        requires!(authorization, :previous_paymt_code, :previous_order_id)
        post = {
          'paymtCode' => authorization[:previous_paymt_code],
          'fncCode' => FNC_CODES[:cancel_order],
          'orderID' => authorization[:previous_order_id] # 6-47 characters, unique per shop_id
        }
        commit(post, authorization[:previous_paymt_code], authorization[:previous_order_id])
      end

      def store(payment, options = {})
        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          requires!(options, :customer)
          post = {
              'paymtCode' => PAYMENT_CODE[:card_membership],
              'fncCode' => FNC_CODES[:member_serv_register_card],
              'cduserID' => options[:customer],
              'retokURL' => 'http://www.example.com', # TODO Dummy, not going to be used?
              'retngURL' => 'http://www.example.com', # TODO Dummy, not going to be used?
              'ordAmount' => localized_amount(100, 'JPY').to_i.to_s, # TODO - Dummy value here OK
              'ordAmountTax' => '0',
          }
          add_econ_payment_page_settings(post, options)
          add_payment(post, payment)
        else
          raise ArgumentError, 'payment must be a Credit card (ActiveMerchant::Billing::CreditCard)'
        end
        commit(post, PAYMENT_CODE[:card_membership], nil)
      end

      def verify(credit_card, options={})
        raise NotImplementedError, 'verify operation is not supported'
      end

      private

      def purchase_or_auth(action, money, payment, options={})
        pCode = ''
        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          requires!(options, :order_id, :description)
          pCode = PAYMENT_CODE[:card_non_membership]
          # Non-membership
          post = {
              'orderDate' => Time.now.getutc.strftime("%Y/%m/%d %H:%M:%S") #yyyy/mm/dd hh:mm:ss
          }
          add_invoice(post, money, options)
          add_econ_payment_page_settings(post, options)
          add_payment(post, payment)
        else
          # Membership
          requires!(options, :order_id)
          pCode = PAYMENT_CODE[:card_membership]
          post = {
              'cduserID' => payment, #single-byte alphanumeric within 36 characters
              'cd3secFlg' => 0 # Do NOT activate 3d secure
          }
          add_invoice(post, money, options)
        end
        post['paymtCode'] = pCode
        post['fncCode'] = action
        post['orderID'] = options[:order_id] # 6-47 characters, unique per shop_id
        post['sessionID'] = options[:order_id]
        commit(post, pCode, options[:order_id])
      end

      def build_capture_post(pCode, fCode, money, options={} )
        {
            'paymtCode' => pCode,
            'fncCode' => fCode,
            'orderID' => options[:order_id], # 6-47 characters, unique per shop_id
            'ordAmount' => localized_amount(money, 'JPY').to_i.to_s, # 1-999999 single-byte characters
            'shipDate' => Time.now.getutc.strftime("%Y/%m/%d") # This is the capture date
        }
      end

      def add_invoice(post, money, options)
        post['itemName'] = options[:description] # single-byte 22 characters
        post['ordAmount'] = localized_amount(money, 'JPY').to_i.to_s # 1-999999 single-byte characters
        post['ordAmountTax'] = '0'
        post['commission'] = '0'
      end

      def add_econ_payment_page_settings(post, options)
        post['ecnEntry'] = 0 # Not utilize ECON payment page
        post['Language'] = 1 # 0 Japanese 1 English # TODO, make configurable?
      end

      def add_payment(post, payment)
        post['econCardno'] = payment.number
        post['cardExpdate'] = "#{payment.year.to_s}#{'%02d' % payment.month}" # 'yyyymm' format
        post['payCnt'] = '00' # Default to 'lump-sum payment'
        post['cd3secFlg'] = 0 # Do NOT activate 3d secure
        post['CVV2'] = '%04d' % payment.verification_value
      end

      def parse(body)

        response = {}

        doc = Nokogiri::XML(CGI.unescapeHTML(body), nil, 'Shift_JIS')
        body = doc.xpath('//result')
        body.children.each do |node|
          if node.text?
            next
          elsif (node.elements.size == 0)
            response[node.name.downcase.to_sym] = node.text.encode('utf-8')
          else
            node.elements.each do |childnode|
              name = "#{node.name.downcase}_#{childnode.name.downcase}"
              response[name.to_sym] = childnode.text.encode('utf-8')
            end
          end
        end
        response
      end

      def commit(parameters, paymt_code, order_id)
        url = (test? ? test_url : @options[:live_url])

        headers = {
            'Content-Type' => 'application/x-www-form-urlencoded;charset=shift_jis'
        }
        response = parse(ssl_post(url, post_data(parameters), headers))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response, paymt_code, order_id),
          test: test?
        )
      end

      def success_from(response)
        result_code_from(response) == STATUS[:success]
      end

      def result_code_from(response)
        response[:status].encode('UTF-8') unless response[:status].nil?
      end

      def message_from(response)
        response[:info].encode('UTF-8') unless response[:info].nil?
      end

      def authorization_from(response, paymt_code, order_id)
        {
            ecn_token: response[:ecnToken],
            user_token: response[:cduserID],
            card_aquirer_code: response[:shimukecd],
            previous_order_id: order_id,
            previous_paymt_code: paymt_code
        }
      end

      def post_data(parameters = {})
        post = {
            'shopID' => @options[:shop_id],
            'chkCode' => @options[:chk_code],
        }
        request = post.merge(parameters).map {|key,value| "#{key}=#{CGI.escape(value.to_s.encode('Shift_JIS'))}"}.join("&")
        request
      end
    end
  end
end
