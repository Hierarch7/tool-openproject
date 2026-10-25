/*
 * -- copyright
 * OpenProject is an open source project management software.
 * Copyright (C) the OpenProject GmbH
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 3.
 *
 * OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
 * Copyright (C) 2006-2013 Jean-Philippe Lang
 * Copyright (C) 2010-2013 the ChiliProject Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * See COPYRIGHT and LICENSE files for more details.
 * ++
 */

import TwoFactorAuthenticationController from './two-factor-authentication.controller';
import { setupStimulusTest, type StimulusTestContext } from 'core-stimulus/test-helpers';

describe('TwoFactorAuthenticationController OTP input', () => {
  let ctx:StimulusTestContext;
  let submissions:Event[];

  beforeEach(async () => {
    ctx = await setupStimulusTest({
      controllers: { 'two-factor-authentication': TwoFactorAuthenticationController },
    });
    submissions = [];
    ctx.container.addEventListener('submit', (event) => {
      if (!event.defaultPrevented) {
        submissions.push(event);
      }
      event.preventDefault();
    });
  });

  afterEach(() => ctx.dispose());

  async function mountOtp(value = '') {
    await ctx.mount(`
      <form data-controller="two-factor-authentication"
            data-device-type="totp"
            data-action="submit->two-factor-authentication#onVerifyDevice">
        <label for="otp">Code</label>
        <div class="auth-form--otp">
          <span class="form--text-field-container">
            <input id="otp" name="otp" value="${value}"
                   data-two-factor-authentication-target="otpInput"
                   data-action="input->two-factor-authentication#updateOtpCells">
          </span>
          <div data-two-factor-authentication-target="otpCells" aria-hidden="true" hidden>
            ${Array.from({ length: 6 }, () => '<span data-two-factor-authentication-target="otpCell"></span>').join('')}
          </div>
        </div>
      </form>
    `);
    return ctx.screen.getByLabelText<HTMLInputElement>('Code');
  }

  function displayedCode() {
    return Array.from(ctx.container.querySelectorAll('[data-two-factor-authentication-target="otpCell"]'))
      .map((cell) => cell.textContent);
  }

  it('displays a prefilled code and reveals the visual cells', async () => {
    await mountOtp('012345');

    expect(displayedCode()).toEqual(['0', '1', '2', '3', '4', '5']);
    expect(ctx.container.querySelector('[data-two-factor-authentication-target="otpCells"]')).not.toHaveAttribute('hidden');
    expect(ctx.container.querySelector('.auth-form--otp')).toHaveClass('auth-form--otp-enhanced');
  });

  it('submits a pasted six-digit code while preserving leading zeros', async () => {
    const input = await mountOtp();

    input.value = '001234';
    input.dispatchEvent(new Event('input', { bubbles: true }));

    expect(displayedCode()).toEqual(['0', '0', '1', '2', '3', '4']);
    expect(new FormData(input.form!).get('otp')).toBe('001234');
    expect(submissions).toHaveLength(1);
  });

  it('focuses the code input when the controller connects', async () => {
    const input = await mountOtp();

    expect(input).toHaveFocus();
  });

  it('waits until all six digits have been entered', async () => {
    const input = await mountOtp();

    for (const code of ['0', '01', '012', '0123', '01234']) {
      input.value = code;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      expect(submissions).toHaveLength(0);
    }

    input.value = '012345';
    input.dispatchEvent(new Event('input', { bubbles: true }));

    expect(submissions).toHaveLength(1);
  });

  it('does not automatically submit invalid or incomplete codes', async () => {
    const input = await mountOtp();

    for (const code of ['', '12345', '1234567', 'abcdef', '12345 ']) {
      input.value = code;
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }

    expect(submissions).toHaveLength(0);
  });

  it('waits until input composition has completed', async () => {
    const input = await mountOtp();
    input.value = '123456';
    input.dispatchEvent(new InputEvent('input', { bubbles: true, isComposing: true }));

    expect(submissions).toHaveLength(0);

    input.dispatchEvent(new InputEvent('input', { bubbles: true, isComposing: false }));

    expect(submissions).toHaveLength(1);
  });

  it('prevents duplicate submissions from input events, Enter, or the submit button', async () => {
    const input = await mountOtp();
    input.value = '123456';

    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.form!.requestSubmit();

    expect(submissions).toHaveLength(1);
  });

  it('clears trailing cells when the user deletes digits', async () => {
    const input = await mountOtp('12345');

    input.value = '12';
    input.dispatchEvent(new Event('input', { bubbles: true }));

    expect(displayedCode()).toEqual(['1', '2', '', '', '', '']);
  });

  it('connects on WebAuthn forms without an OTP input', async () => {
    await ctx.mount('<form data-controller="two-factor-authentication"></form>');

    expect(ctx.container.querySelector('.auth-form--otp-enhanced')).toBeNull();
  });
});
