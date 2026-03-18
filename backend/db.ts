import { createClient, type SupabaseClient } from "@supabase/supabase-js";

interface Database {
  public: {
    Tables: {
      users: {
        Row: DbUser;
        Insert: Omit<DbUser, "id" | "created_at">;
        Update: Partial<Omit<DbUser, "id" | "created_at">>;
      };
      connections: {
        Row: DbConnection;
        Insert: Omit<DbConnection, "id" | "created_at">;
        Update: Partial<Omit<DbConnection, "id" | "created_at">>;
      };
      shares: {
        Row: DbShare;
        Insert: Omit<DbShare, "id" | "created_at">;
        Update: Partial<Omit<DbShare, "id" | "created_at">>;
      };
      songs: {
        Row: DbSong;
        Insert: Omit<DbSong, "id">;
        Update: Partial<Omit<DbSong, "id">>;
      };
    };
  };
}

let supabaseInstance: SupabaseClient<Database> | null = null;

function supabase() {
  if (!supabaseInstance) {
    const url = process.env.SUPABASE_URL ?? process.env.EXPO_PUBLIC_SUPABASE_URL ?? "";
    const key = process.env.SUPABASE_ANON_KEY ?? process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? "";
    supabaseInstance = createClient<Database>(url, key);
  }
  return supabaseInstance;
}

export interface DbUser {
  id: string;
  phone: string;
  first_name: string;
  username: string;
  created_at: string;
}

export interface DbConnection {
  id: string;
  user_a_id: string;
  user_b_id: string;
  created_at: string;
}

export interface DbShare {
  id: string;
  sender_id: string;
  recipient_id: string;
  song_id: string;
  note: string | null;
  created_at: string;
}

export interface DbSong {
  id: string;
  title: string;
  artist: string;
  album_art_url: string;
  duration: string;
}

function mapUser(row: DbUser) {
  return {
    id: row.id,
    phone: row.phone,
    firstName: row.first_name,
    username: row.username,
    createdAt: row.created_at,
  };
}

function mapSong(row: DbSong) {
  return {
    id: row.id,
    title: row.title,
    artist: row.artist,
    albumArtURL: row.album_art_url,
    duration: row.duration,
  };
}

function mapShare(row: DbShare) {
  return {
    id: row.id,
    senderId: row.sender_id,
    recipientId: row.recipient_id,
    songId: row.song_id,
    note: row.note,
    createdAt: row.created_at,
  };
}

export const db = {
  songs: {
    getAll: async () => {
      const { data, error } = await supabase().from("songs").select("*");
      if (error) throw error;
      return (data as DbSong[]).map(mapSong);
    },
    getById: async (id: string) => {
      const { data, error } = await supabase().from("songs").select("*").eq("id", id).single();
      if (error) return undefined;
      return mapSong(data as DbSong);
    },
    search: async (query: string) => {
      if (!query) return db.songs.getAll();
      const q = `%${query}%`;
      const { data, error } = await supabase()
        .from("songs")
        .select("*")
        .or(`title.ilike.${q},artist.ilike.${q}`);
      if (error) throw error;
      return (data as DbSong[]).map(mapSong);
    },
  },

  users: {
    getById: async (id: string) => {
      const { data, error } = await supabase().from("users").select("*").eq("id", id).single();
      if (error) return undefined;
      return mapUser(data as DbUser);
    },
    getByPhone: async (phone: string) => {
      const { data, error } = await supabase().from("users").select("*").eq("phone", phone).single();
      if (error) return undefined;
      return mapUser(data as DbUser);
    },
    getByUsername: async (username: string) => {
      const { data, error } = await supabase().from("users").select("*").eq("username", username).single();
      if (error) return undefined;
      return mapUser(data as DbUser);
    },
    create: async (input: { phone: string; firstName: string; username: string }) => {
      const { data, error } = await supabase()
        .from("users")
        .insert({ phone: input.phone, first_name: input.firstName, username: input.username } as any)
        .select("*")
        .single();
      if (error) throw error;
      return mapUser(data as DbUser);
    },
    searchByUsername: async (query: string) => {
      if (!query) return [];
      const q = `%${query}%`;
      const { data, error } = await supabase()
        .from("users")
        .select("*")
        .or(`username.ilike.${q},first_name.ilike.${q}`);
      if (error) throw error;
      return (data as DbUser[]).map(mapUser);
    },
    checkUsername: async (username: string) => {
      const { data } = await supabase().from("users").select("id").eq("username", username).single();
      return !data;
    },
  },

  connections: {
    exists: async (userAId: string, userBId: string) => {
      const { data } = await supabase()
        .from("connections")
        .select("id")
        .or(`and(user_a_id.eq.${userAId},user_b_id.eq.${userBId}),and(user_a_id.eq.${userBId},user_b_id.eq.${userAId})`)
        .limit(1);
      return (data && data.length > 0) || false;
    },
    create: async (userAId: string, userBId: string) => {
      const { data, error } = await supabase()
        .from("connections")
        .insert({ user_a_id: userAId, user_b_id: userBId } as any)
        .select("*")
        .single();
      if (error) throw error;
      return data;
    },
    getFriends: async (userId: string): Promise<ReturnType<typeof mapUser>[]> => {
      const { data, error } = await supabase()
        .from("connections")
        .select("*")
        .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`);
      if (error) throw error;
      const friendIds = (data as DbConnection[]).map(c =>
        c.user_a_id === userId ? c.user_b_id : c.user_a_id
      );
      if (friendIds.length === 0) return [];
      const { data: friends, error: fErr } = await supabase()
        .from("users")
        .select("*")
        .in("id", friendIds);
      if (fErr) throw fErr;
      return (friends as DbUser[]).map(mapUser);
    },
  },

  shares: {
    create: async (input: { senderId: string; recipientId: string; songId: string; note: string | null }) => {
      const { data, error } = await supabase()
        .from("shares")
        .insert({
          sender_id: input.senderId,
          recipient_id: input.recipientId,
          song_id: input.songId,
          note: input.note,
        } as any)
        .select("*")
        .single();
      if (error) throw error;
      const exists = await db.connections.exists(input.senderId, input.recipientId);
      if (!exists) {
        await db.connections.create(input.senderId, input.recipientId);
      }
      return mapShare(data as DbShare);
    },
    getReceived: async (userId: string) => {
      const { data, error } = await supabase()
        .from("shares")
        .select("*")
        .eq("recipient_id", userId)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data as DbShare[]).map(mapShare);
    },
    getSent: async (userId: string) => {
      const { data, error } = await supabase()
        .from("shares")
        .select("*")
        .eq("sender_id", userId)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data as DbShare[]).map(mapShare);
    },
    getById: async (id: string) => {
      const { data, error } = await supabase().from("shares").select("*").eq("id", id).single();
      if (error) return undefined;
      return mapShare(data as DbShare);
    },
  },
};
