const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

exports.sendNotification = functions.https.onRequest(async (req, res) => {
  const { token, title, body } = req.body;

  if (!token || !title || !body) {
    res.status(400).send('Missing parameters');
    return;
  }

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: { click_action: 'FLUTTER_NOTIFICATION_CLICK' },
    });
    res.status(200).send('Notification sent');
  } catch (err) {
    console.error('Notification error:', err);
    res.status(500).send('Notification error');
  }
});
