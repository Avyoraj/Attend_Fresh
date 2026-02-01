-- =============================================
-- Auto-Attend: Frictionless BLE Attendance System
-- Complete Updated Schema for New Flow
-- =============================================


CREATE TABLE IF NOT EXISTS teachers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  department TEXT DEFAULT 'General',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  email TEXT,
  year INTEGER,
  section TEXT,
  device_id TEXT UNIQUE,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  building TEXT,
  floor TEXT,
  capacity INTEGER DEFAULT 50,
  beacon_uuid TEXT DEFAULT '215d0698-0b3d-34a6-a844-5ce2b2447f1a',
  beacon_major INTEGER NOT NULL,
  beacon_minor INTEGER NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(beacon_major, beacon_minor)
);


CREATE TABLE IF NOT EXISTS classes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  subject TEXT,
  teacher_id UUID REFERENCES teachers(id),
  room_id TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id TEXT NOT NULL,
  class_id TEXT NOT NULL,
  class_name TEXT NOT NULL,
  teacher_id UUID REFERENCES teachers(id),
  teacher_name TEXT NOT NULL,
  beacon_major INTEGER NOT NULL,
  beacon_minor INTEGER NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'ended', 'cancelled')),
  actual_start TIMESTAMPTZ DEFAULT now(),
  actual_end TIMESTAMPTZ,
  session_date DATE DEFAULT CURRENT_DATE,
  stats JSONB DEFAULT '{"total": 0, "confirmed": 0, "provisional": 0}',
  created_at TIMESTAMPTZ DEFAULT now()
);


CREATE UNIQUE INDEX IF NOT EXISTS idx_active_session_per_room 
ON sessions(room_id) WHERE status = 'active';

-- 6. ATTENDANCE TABLE (Updated for New Flow)
CREATE TABLE IF NOT EXISTS attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id TEXT NOT NULL,
  class_id TEXT NOT NULL,
  session_id UUID REFERENCES sessions(id),
  device_id TEXT NOT NULL,
  -- Expanded statuses for digital analysis and physical lock
  status TEXT DEFAULT 'provisional' 
    CHECK (status IN ('provisional', 'flagged', 'pending_physical', 'confirmed', 'cancelled', 'manual', 'absent')),
  check_in_time TIMESTAMPTZ DEFAULT now(),
  confirmed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,
  -- Physical/Biometric Verification Fields
  biometric_verified_at TIMESTAMPTZ,
  physical_verified_by UUID REFERENCES teachers(id),
  rssi INTEGER,
  distance NUMERIC(5,2),
  beacon_major INTEGER,
  beacon_minor INTEGER,
  session_date DATE DEFAULT CURRENT_DATE,
  is_manual BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(student_id, class_id, session_date)
);


CREATE TABLE IF NOT EXISTS rssi_streams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id TEXT NOT NULL,
  class_id TEXT NOT NULL,
  session_date DATE DEFAULT CURRENT_DATE,
  rssi_data JSONB NOT NULL DEFAULT '[]',
  sample_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS anomalies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id_1 TEXT NOT NULL,
  student_id_2 TEXT NOT NULL,
  class_id TEXT NOT NULL,
  session_date DATE NOT NULL,
  correlation_score NUMERIC(4,3) NOT NULL,
  severity TEXT DEFAULT 'warning' CHECK (severity IN ('warning', 'critical')),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed_proxy', 'false_positive', 'investigating')),
  reviewed_by UUID REFERENCES teachers(id),
  reviewed_at TIMESTAMPTZ,
  notes TEXT,
  rssi_data_1 JSONB,
  rssi_data_2 JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_attendance_student ON attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_class ON attendance(class_id);
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(session_date);
CREATE INDEX IF NOT EXISTS idx_sessions_beacon ON sessions(beacon_major, beacon_minor);
CREATE INDEX IF NOT EXISTS idx_rssi_student_class ON rssi_streams(student_id, class_id, session_date);

ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE rssi_streams ENABLE ROW LEVEL SECURITY;
ALTER TABLE anomalies ENABLE ROW LEVEL SECURITY;

-- Basic Policies
CREATE POLICY "Public Read" ON rooms FOR SELECT USING (true);
CREATE POLICY "Public Read Students" ON students FOR SELECT USING (true);
CREATE POLICY "Active sessions viewable" ON sessions FOR SELECT USING (status = 'active');
CREATE POLICY "Anyone can insert attendance" ON attendance FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update attendance" ON attendance FOR UPDATE USING (true);
CREATE POLICY "Anyone can insert rssi" ON rssi_streams FOR INSERT WITH CHECK (true);