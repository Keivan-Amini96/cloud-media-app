#!/bin/bash

# Set project and zone
PROJECT_ID="p18-18"
ZONE="us-east1"
CLUSTER_NAME="nginx-service"

# Create directory structure
echo "Creating directory structure..."
mkdir -p ~/social-media-app/{backend,frontend/src}
cd ~/social-media-app

# Create backend files
echo "Creating backend files..."
cat > backend/Dockerfile << 'EOL'
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
EOL

cat > backend/server.js << 'EOL'
const express = require('express');
const { initializeApp } = require('firebase/app');
const { getFirestore } = require('firebase/firestore');
const { getStorage } = require('firebase/storage');
const { getAuth } = require('firebase/auth');

const firebaseConfig = {
  apiKey: process.env.FIREBASE_API_KEY,
  authDomain: process.env.FIREBASE_AUTH_DOMAIN,
  projectId: process.env.FIREBASE_PROJECT_ID,
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET
};

const app = express();
const firebaseApp = initializeApp(firebaseConfig);
const db = getFirestore(firebaseApp);
const storage = getStorage(firebaseApp);
const auth = getAuth(firebaseApp);

app.get('/healthz', (req, res) => res.send('OK'));
app.listen(3000, () => console.log('Server running on port 3000'));
EOL

cat > backend/package.json << 'EOL'
{
  "name": "backend",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.17.1",
    "firebase": "^9.6.0",
    "cors": "^2.8.5"
  }
}
EOL

# Create frontend files
echo "Creating frontend files..."
cat > frontend/Dockerfile << 'EOL'
FROM node:16 as build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOL

cat > frontend/src/App.js << 'EOL'
import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, signInWithPopup } from 'firebase/auth';

const firebaseConfig = {
  apiKey: process.env.REACT_APP_API_KEY,
  authDomain: process.env.REACT_APP_AUTH_DOMAIN,
  projectId: process.env.REACT_APP_PROJECT_ID,
  storageBucket: process.env.REACT_APP_STORAGE_BUCKET
};

function App() {
  const signIn = async () => {
    const provider = new GoogleAuthProvider();
    await signInWithPopup(getAuth(), provider);
  };

  return (
    <div>
      <h1>Social Media App</h1>
      <button onClick={signIn}>Sign in with Google</button>
    </div>
  );
}

export default App;
EOL

cat > frontend/package.json << 'EOL'
{
  "name": "frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "firebase": "^9.6.0",
    "react": "^17.0.2",
    "react-dom": "^17.0.2",
    "react-scripts": "5.0.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  }
}
EOL

# Enable required GCP services
echo "Enabling GCP services..."
gcloud services enable \
  container.googleapis.com \
  firestore.googleapis.com \
  firebase.googleapis.com \
  storage-component.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com

# Set current project
echo "Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $ZONE

# Get Firebase Web API Key
echo -e "\n\nGET YOUR FIREBASE API KEY:"
echo "1. Go to: https://console.firebase.google.com/project/$PROJECT_ID/settings/general"
echo "2. Under 'Your apps' section, click the web app (or create one)"
echo "3. Copy the 'apiKey' value from the config object"
echo -e "\nPaste your Firebase API key here and press Enter:"
read FIREBASE_API_KEY

# Build and push Docker images
echo "Building and pushing Docker images..."

# Build backend
cd backend
npm install
docker build -t gcr.io/$PROJECT_ID/backend .
docker push gcr.io/$PROJECT_ID/backend
cd ..

# Build frontend
cd frontend
npm install
npm run build
docker build -t gcr.io/$PROJECT_ID/frontend .
docker push gcr.io/$PROJECT_ID/frontend
cd ..

# Connect to GKE cluster
echo "Connecting to GKE cluster..."
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

# Create Firebase config ConfigMap
echo "Creating Firebase ConfigMap..."
kubectl create configmap firebase-config \
  --from-literal=FIREBASE_API_KEY=$FIREBASE_API_KEY \
  --from-literal=FIREBASE_PROJECT_ID=$PROJECT_ID \
  --from-literal=FIREBASE_STORAGE_BUCKET="$PROJECT_ID.appspot.com" \
  --from-literal=FIREBASE_AUTH_DOMAIN="$PROJECT_ID.firebaseapp.com"

# Deploy backend
echo "Deploying backend..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: gcr.io/$PROJECT_ID/backend
        ports:
        - containerPort: 3000
        envFrom:
        - configMapRef:
            name: firebase-config
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /healthz
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  selector:
    app: backend
  ports:
    - protocol: TCP
      port: 3000
      targetPort: 3000
EOF

# Deploy frontend
echo "Deploying frontend..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: gcr.io/$PROJECT_ID/frontend
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: firebase-config
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF

# Setup Firebase services
echo "Setting up Firebase services..."

# Initialize Firestore
echo "Creating Firestore database..."
gcloud firestore databases create --region=nam5 --project=$PROJECT_ID

# Setup Firebase Authentication
echo "Enabling Google Authentication..."
firebase auth:enable --project=$PROJECT_ID google

# Setup Firebase Storage
echo "Setting up Firebase Storage..."
cat <<EOF > storage.rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
EOF
firebase deploy --only storage:rules --project=$PROJECT_ID

# Get frontend service external IP
echo "Getting frontend external IP..."
FRONTEND_IP=$(kubectl get svc frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo -e "\n\nDEPLOYMENT COMPLETE!"
echo -e "\nFrontend will be available at: http://$FRONTEND_IP"
echo -e "\nNext steps:"
echo "1. Visit the frontend URL above"
echo "2. Configure Firebase Authentication methods in Firebase Console"
echo "3. Add your custom domain in Firebase Hosting if needed"