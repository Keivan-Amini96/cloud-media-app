import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";

const firebaseConfig = {
  apiKey: "AIzaSyCyNMs1kclZEIRwKNmFGle-E0uAyikenmw",
  authDomain: "p18-18.firebaseapp.com",
  projectId: "p18-18",
  storageBucket: "p18-18.firebasestorage.app",
  messagingSenderId: "731106782115",
  appId: "1:731106782115:web:fb2078ebc2728b3f674816",
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
