export interface DbUser {
  id: string;
  phone: string;
  firstName: string;
  username: string;
  createdAt: string;
}

export interface DbConnection {
  id: string;
  userAId: string;
  userBId: string;
  createdAt: string;
}

export interface DbShare {
  id: string;
  senderId: string;
  recipientId: string;
  songId: string;
  note: string | null;
  createdAt: string;
}

export interface DbSong {
  id: string;
  title: string;
  artist: string;
  albumArtURL: string;
  duration: string;
}

const users: Map<string, DbUser> = new Map();
const connections: Map<string, DbConnection> = new Map();
const shares: Map<string, DbShare> = new Map();

const songs: DbSong[] = [
  { id: "1", title: "Can't Help Myself", artist: "Kita Alexander", albumArtURL: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&h=600&fit=crop", duration: "3:15" },
  { id: "2", title: "Whispers in the Pines", artist: "Luna & The Woods", albumArtURL: "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&h=600&fit=crop", duration: "3:22" },
  { id: "3", title: "City Lights in the Rain", artist: "Neon Eclipse", albumArtURL: "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=600&h=600&fit=crop", duration: "4:34" },
  { id: "4", title: "Moments & Motion", artist: "Jade Rivers", albumArtURL: "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=600&fit=crop", duration: "3:48" },
  { id: "5", title: "Golden Hour", artist: "Mystic Source", albumArtURL: "https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=600&h=600&fit=crop", duration: "4:12" },
  { id: "6", title: "Midnight Drive", artist: "The Velvet Haze", albumArtURL: "https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=600&h=600&fit=crop", duration: "3:56" },
  { id: "7", title: "Bloom", artist: "Pale Winter", albumArtURL: "https://images.unsplash.com/photo-1484755560615-a4c64e778a6c?w=600&h=600&fit=crop", duration: "3:30" },
  { id: "8", title: "Echoes of You", artist: "Dream Coast", albumArtURL: "https://images.unsplash.com/photo-1506157786151-b8491531f063?w=600&h=600&fit=crop", duration: "4:05" },
  { id: "9", title: "Slow Burn", artist: "Amber Skies", albumArtURL: "https://images.unsplash.com/photo-1446057032654-9d8885db76c6?w=600&h=600&fit=crop", duration: "3:42" },
  { id: "10", title: "Neon Dreams", artist: "Glass Animals Jr.", albumArtURL: "https://images.unsplash.com/photo-1504898770365-14faca6a7320?w=600&h=600&fit=crop", duration: "4:18" },
  { id: "11", title: "Paper Planes", artist: "Wild Nothing", albumArtURL: "https://images.unsplash.com/photo-1485579149621-3123dd979885?w=600&h=600&fit=crop", duration: "3:10" },
  { id: "12", title: "Coastline", artist: "Tidal Wave", albumArtURL: "https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=600&h=600&fit=crop", duration: "3:55" },
  { id: "13", title: "After Dark", artist: "Noir Collective", albumArtURL: "https://images.unsplash.com/photo-1415201364774-f6f0bb35f28f?w=600&h=600&fit=crop", duration: "4:25" },
  { id: "14", title: "Satellite", artist: "Cosmic Drift", albumArtURL: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=600&h=600&fit=crop", duration: "3:38" },
  { id: "15", title: "Honey", artist: "Still Corners", albumArtURL: "https://images.unsplash.com/photo-1453090927415-5f45085b65c0?w=600&h=600&fit=crop", duration: "4:01" },
];

export const db = {
  songs: {
    getAll: () => songs,
    getById: (id: string) => songs.find(s => s.id === id),
    search: (query: string) => {
      if (!query) return songs;
      const q = query.toLowerCase();
      return songs.filter(s =>
        s.title.toLowerCase().includes(q) || s.artist.toLowerCase().includes(q)
      );
    },
  },

  users: {
    getById: (id: string) => users.get(id),
    getByPhone: (phone: string) => Array.from(users.values()).find(u => u.phone === phone),
    getByUsername: (username: string) => Array.from(users.values()).find(u => u.username === username),
    create: (data: { phone: string; firstName: string; username: string }): DbUser => {
      const id = crypto.randomUUID();
      const user: DbUser = { id, ...data, createdAt: new Date().toISOString() };
      users.set(id, user);
      return user;
    },
    searchByUsername: (query: string) => {
      if (!query) return [];
      const q = query.toLowerCase();
      return Array.from(users.values()).filter(u =>
        u.username.toLowerCase().includes(q) || u.firstName.toLowerCase().includes(q)
      );
    },
    checkUsername: (username: string) => !Array.from(users.values()).some(u => u.username === username),
  },

  connections: {
    getForUser: (userId: string) => {
      return Array.from(connections.values()).filter(
        c => c.userAId === userId || c.userBId === userId
      );
    },
    exists: (userAId: string, userBId: string) => {
      return Array.from(connections.values()).some(
        c => (c.userAId === userAId && c.userBId === userBId) ||
             (c.userAId === userBId && c.userBId === userAId)
      );
    },
    create: (userAId: string, userBId: string): DbConnection => {
      const id = crypto.randomUUID();
      const conn: DbConnection = { id, userAId, userBId, createdAt: new Date().toISOString() };
      connections.set(id, conn);
      return conn;
    },
    getFriends: (userId: string): DbUser[] => {
      const conns = Array.from(connections.values()).filter(
        c => c.userAId === userId || c.userBId === userId
      );
      return conns.map(c => {
        const friendId = c.userAId === userId ? c.userBId : c.userAId;
        return users.get(friendId);
      }).filter(Boolean) as DbUser[];
    },
  },

  shares: {
    create: (data: { senderId: string; recipientId: string; songId: string; note: string | null }): DbShare => {
      const id = crypto.randomUUID();
      const share: DbShare = { id, ...data, createdAt: new Date().toISOString() };
      shares.set(id, share);
      if (!db.connections.exists(data.senderId, data.recipientId)) {
        db.connections.create(data.senderId, data.recipientId);
      }
      return share;
    },
    getReceived: (userId: string) => {
      return Array.from(shares.values())
        .filter(s => s.recipientId === userId)
        .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    },
    getSent: (userId: string) => {
      return Array.from(shares.values())
        .filter(s => s.senderId === userId)
        .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    },
    getById: (id: string) => shares.get(id),
  },
};
