import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import NavBar from "./components/NavBar";
import Feed from "./pages/Feed";
import PostDetail from "./pages/PostDetail";
import NewPost from "./pages/NewPost";
import EditPost from "./pages/EditPost";
import Callback from "./pages/Callback";
import Profile from "./pages/Profile";
import Settings from "./pages/Settings";
import MyFeed from "./pages/MyFeed";
import Notifications from "./pages/Notifications";
import ModerationQueue from "./pages/ModerationQueue";
import TagPosts from "./pages/TagPosts";
import { isAuthenticated, isAdmin } from "./lib/auth";

function RequireAuth({ children }) {
  return isAuthenticated() ? children : <Navigate to="/" replace />;
}

function RequireAdmin({ children }) {
  return isAuthenticated() && isAdmin() ? children : <Navigate to="/" replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <NavBar />
      <main>
        <Routes>
          <Route path="/" element={<Feed />} />
          <Route path="/posts/:postId" element={<PostDetail />} />
          <Route
            path="/posts/:postId/edit"
            element={
              <RequireAuth>
                <EditPost />
              </RequireAuth>
            }
          />
          <Route
            path="/new"
            element={
              <RequireAuth>
                <NewPost />
              </RequireAuth>
            }
          />
          <Route path="/tags/:tag" element={<TagPosts />} />
          <Route path="/u/:username" element={<Profile />} />
          <Route path="/callback" element={<Callback />} />
          <Route
            path="/settings"
            element={
              <RequireAuth>
                <Settings />
              </RequireAuth>
            }
          />
          <Route
            path="/me/feed"
            element={
              <RequireAuth>
                <MyFeed />
              </RequireAuth>
            }
          />
          <Route
            path="/me/notifications"
            element={
              <RequireAuth>
                <Notifications />
              </RequireAuth>
            }
          />
          <Route
            path="/admin/moderation"
            element={
              <RequireAdmin>
                <ModerationQueue />
              </RequireAdmin>
            }
          />
        </Routes>
      </main>
    </BrowserRouter>
  );
}
