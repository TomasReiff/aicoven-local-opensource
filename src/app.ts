import { initializeApp } from 'firebase/app';
import { getAuth, signInAnonymously } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { trackAppOpened } from './analytics';

const firebaseConfig = {
  // your firebase config
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

async function main() {
  await signInAnonymously(auth);
  console.log('Signed in anonymously');

  trackAppOpened();

  // Your app logic here
}

main();