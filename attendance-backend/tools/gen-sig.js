// Signature Generator for Testing
// Usage: node tools/gen-sig.js <deviceId> <secret>

const crypto = require('crypto');

const deviceId = process.argv[2] || 'TEST_DEVICE';
const secret = process.argv[3] || 'my_secret_salt';

const signature = crypto
  .createHmac('sha256', secret)
  .update(deviceId)
  .digest('hex');

console.log('\n=== Signature Generator ===');
console.log('Device ID:', deviceId);
console.log('Secret:', secret);
console.log('Signature:', signature);
console.log('\nUse this signature in Postman!\n');
