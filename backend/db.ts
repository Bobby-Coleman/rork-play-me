import { supabase } from "./supabase";

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

export const db = {
  songs: {
    getAll: async (): Promise<DbSong[]> => {
      const { data, error } = await supabase.from("songs").select("*").order("id");
      if (error) throw error;
      return data ?? [];
    },
    getById: async (id: string): Promise<DbSong | null> => {
      const { data, error } = await supabase.from("songs").select("*").eq("id", id).single();
      if (error) return null;
      return data;
    },
    search: async (query: string): Promise<DbSong[]> => {
      if (!query) return db.songs.getAll();
      const { data, error } = await supabase
        .from("songs")
        .select("*")
        .or(`title.ilike.%${query}%,artist.ilike.%${query}%`)
        .order("id");
      if (error) throw error;
      return data ?? [];
    },
  },

  users: {
    getById: async (id: string): Promise<DbUser | null> => {
      const { data, error } = await supabase.from("users").select("*").eq("id", id).single();
      if (error) return null;
      return data;
    },
    getByPhone: async (phone: string): Promise<DbUser | null> => {
      const { data, error } = await supabase.from("users").select("*").eq("phone", phone).single();
      if (error) return null;
      return data;
    },
    create: async (input: { phone: string; first_name: string; username: string }): Promise<DbUser> => {
      const { data, error } = await supabase.from("users").insert(input).select().single();
      if (error) throw error;
      return data;
    },
    searchByUsername: async (query: string): Promise<DbUser[]> => {
      if (!query) return [];
      const { data, error } = await supabase
        .from("users")
        .select("*")
        .or(`username.ilike.%${query}%,first_name.ilike.%${query}%`);
      if (error) throw error;
      return data ?? [];
    },
    checkUsername: async (username: string): Promise<boolean> => {
      const { data, error } = await supabase.from("users").select("id").eq("username", username).maybeSingle();
      if (error) throw error;
      return data === null;
    },
  },

  connections: {
    exists: async (userAId: string, userBId: string): Promise<boolean> => {
      const { data, error } = await supabase
        .from("connections")
        .select("id")
        .or(
          `and(user_a_id.eq.${userAId},user_b_id.eq.${userBId}),and(user_a_id.eq.${userBId},user_b_id.eq.${userAId})`
        )
        .maybeSingle();
      if (error) return false;
      return data !== null;
    },
    create: async (userAId: string, userBId: string): Promise<DbConnection> => {
      const { data, error } = await supabase
        .from("connections")
        .insert({ user_a_id: userAId, user_b_id: userBId })
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    getFriends: async (userId: string): Promise<DbUser[]> => {
      const { data: conns, error } = await supabase
        .from("connections")
        .select("*")
        .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`);
      if (error) throw error;
      if (!conns || conns.length === 0) return [];

      const friendIds = conns.map((c: DbConnection) =>
        c.user_a_id === userId ? c.user_b_id : c.user_a_id
      );
      const { data: friends, error: friendsError } = await supabase
        .from("users")
        .select("*")
        .in("id", friendIds);
      if (friendsError) throw friendsError;
      return friends ?? [];
    },
  },

  shares: {
    create: async (input: {
      sender_id: string;
      recipient_id: string;
      song_id: string;
      note: string | null;
    }): Promise<DbShare> => {
      const { data, error } = await supabase.from("shares").insert(input).select().single();
      if (error) throw error;

      const connected = await db.connections.exists(input.sender_id, input.recipient_id);
      if (!connected) {
        await db.connections.create(input.sender_id, input.recipient_id);
      }
      return data;
    },
    getReceived: async (userId: string): Promise<DbShare[]> => {
      const { data, error } = await supabase
        .from("shares")
        .select("*")
        .eq("recipient_id", userId)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
    getSent: async (userId: string): Promise<DbShare[]> => {
      const { data, error } = await supabase
        .from("shares")
        .select("*")
        .eq("sender_id", userId)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
    getById: async (id: string): Promise<DbShare | null> => {
      const { data, error } = await supabase.from("shares").select("*").eq("id", id).single();
      if (error) return null;
      return data;
    },
  },
};
