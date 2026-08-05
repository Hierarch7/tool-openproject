# frozen_string_literal: true

require "rqrcode"

module TwoFactorAuthentication
  module Devices
    # Draws the enrolment code as inline SVG rather than letting the browser paint it, so that
    # it does not depend on canvas, on JavaScript, or on a lazily loaded Stimulus chunk.
    class TotpQrCodeComponent < ViewComponent::Base
      # Rendered edge length of the code, in CSS pixels.
      SIZE = 250

      # Error correction level. High keeps the code scannable when partially obscured.
      ERROR_CORRECTION_LEVEL = :h

      # Quiet zone around the code, in modules. The QR spec asks for 4, which costs a lot of
      # area at this size; 2 still scans reliably against the white background we draw below.
      QUIET_ZONE = 2

      def initialize(device:)
        super()
        @device = device
      end

      def extent
        @extent ||= qr_code.qrcode.module_count + (2 * QUIET_ZONE)
      end

      def modules_path
        # Only the encoded modules end up in the path, so this carries no user input.
        qr_code
          .as_svg(standalone: false, use_path: true, module_size: 1, offset: QUIET_ZONE, color: "222222")
          .html_safe # rubocop:disable Rails/OutputSafety
      end

      private

      def qr_code
        @qr_code ||= RQRCode::QRCode.new(@device.provisioning_url, level: ERROR_CORRECTION_LEVEL)
      end
    end
  end
end
