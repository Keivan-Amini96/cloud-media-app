import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut } from 'firebase/auth';
import { getFirestore, collection, addDoc, query, onSnapshot } from 'firebase/firestore';
import { getStorage, ref, uploadBytes, getDownloadURL } from 'firebase/storage';
import { useState, useEffect } from 'react';

const firebaseConfig = {
  apiKey: process.env.REACT_APP_API_KEY,
  authDomain: process.env.REACT_APP_AUTH_DOMAIN,
  projectId: process.env.REACT_APP_PROJECT_ID,
  storageBucket: process.env.REACT_APP_STORAGE_BUCKET
};

// Initialize Firebase services
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const storage = getStorage(app);

function App() {
  const [user, setUser] = useState(null);
  const [posts, setPosts] = useState([]);
  const [postText, setPostText] = useState('');
  const [imageFile, setImageFile] = useState(null);
  const [loading, setLoading] = useState(false);

  // Handle user auth state
  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged((user) => {
      setUser(user);
      if (user) loadPosts();
    });
    return () => unsubscribe();
  }, []);

  // Load posts from Firestore
  const loadPosts = () => {
    const q = query(collection(db, 'posts'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const postsData = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      setPosts(postsData);
    });
    return unsubscribe;
  };

  // Sign in with Google
  const handleSignIn = async () => {
    try {
      const provider = new GoogleAuthProvider();
      await signInWithPopup(auth, provider);
    } catch (error) {
      console.error("Sign-in error:", error);
    }
  };

  // Sign out
  const handleSignOut = async () => {
    try {
      await signOut(auth);
    } catch (error) {
      console.error("Sign-out error:", error);
    }
  };

  // Create a new post
  const handleCreatePost = async (e) => {
    e.preventDefault();
    if (!postText.trim()) return;

    setLoading(true);
    try {
      let imageUrl = null;
      
      if (imageFile) {
        const storageRef = ref(storage, `posts/${user.uid}/${Date.now()}`);
        await uploadBytes(storageRef, imageFile);
        imageUrl = await getDownloadURL(storageRef);
      }

      await addDoc(collection(db, 'posts'), {
        text: postText,
        imageUrl,
        author: user.displayName,
        userId: user.uid,
        createdAt: new Date(),
        likes: []
      });

      setPostText('');
      setImageFile(null);
    } catch (error) {
      console.error("Error creating post:", error);
    } finally {
      setLoading(false);
    }
  };

  // Like a post
  const handleLike = async (postId) => {
    if (!user) return;
    
    try {
      // Implement your like logic here
      // This would typically update the post document in Firestore
      console.log(`Liked post ${postId}`);
    } catch (error) {
      console.error("Error liking post:", error);
    }
  };

  return (
    <div className="app">
      <header>
        <h1>Social Media App</h1>
        {user ? (
          <button onClick={handleSignOut}>Sign Out</button>
        ) : (
          <button onClick={handleSignIn}>Sign in with Google</button>
        )}
      </header>

      {user && (
        <main>
          {/* Post Creation Form */}
          <form onSubmit={handleCreatePost} className="post-form">
            <textarea
              value={postText}
              onChange={(e) => setPostText(e.target.value)}
              placeholder="What's on your mind?"
              disabled={loading}
            />
            <input
              type="file"
              accept="image/*"
              onChange={(e) => setImageFile(e.target.files[0])}
              disabled={loading}
            />
            <button type="submit" disabled={loading || !postText.trim()}>
              {loading ? 'Posting...' : 'Post'}
            </button>
          </form>

          {/* Posts Feed */}
          <div className="posts-feed">
            {posts.map((post) => (
              <div key={post.id} className="post">
                <h3>{post.author}</h3>
                <p>{post.text}</p>
                {post.imageUrl && (
                  <img src={post.imageUrl} alt="Post" className="post-image" />
                )}
                <button 
                  onClick={() => handleLike(post.id)}
                  className="like-button"
                >
                  Like ({post.likes?.length || 0})
                </button>
              </div>
            ))}
          </div>
        </main>
      )}
    </div>
  );
}

export default App;