// src/utils/security.js
const crypto = require('crypto');
require('dotenv').config();

/**
 * 🛡️ Verify Device Signature
 * Ensures the check-in request actually came from the registered device.
 */
exports.verifyDeviceSignature = ({ deviceId, signature }) => {
  if (!signature || !deviceId) return { valid: false };

  // Use the secret salt from your .env file
  const secret = process.env.DEVICE_SALT_SECRET || 'default_salt';
  
  const expectedSignature = crypto
    .createHmac('sha256', secret)
    .update(deviceId)
    .digest('hex');

  return { valid: signature === expectedSignature };
};