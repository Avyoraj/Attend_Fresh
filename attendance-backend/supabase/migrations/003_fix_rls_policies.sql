-- =============================================
-- Migration 003: Fix RLS policies
-- Drops the restrictive policies from 001 and ensures
-- all required permissive policies exist.
-- Run this in the Supabase SQL Editor.
-- =============================================

-- Drop restrictive policies from 001 that conflict with 002
DROP POLICY IF EXISTS "Active sessions viewable" ON sessions;
DROP POLICY IF EXISTS "Public Read" ON rooms;
DROP POLICY IF EXISTS "Public Read Students" ON students;
DROP POLICY IF EXISTS "Anyone can insert attendance" ON attendance;
DROP POLICY IF EXISTS "Anyone can update attendance" ON attendance;
DROP POLICY IF EXISTS "Anyone can insert rssi" ON rssi_streams;

-- Drop 002 policies if they exist (so we can recreate cleanly)
DROP POLICY IF EXISTS "Students read own profile" ON students;
DROP POLICY IF EXISTS "Anyone can insert students" ON students;
DROP POLICY IF EXISTS "Students update own profile" ON students;
DROP POLICY IF EXISTS "Teachers read own profile" ON teachers;
DROP POLICY IF EXISTS "Anyone can insert teachers" ON teachers;
DROP POLICY IF EXISTS "Teachers update own profile" ON teachers;
DROP POLICY IF EXISTS "Public read classes" ON classes;
DROP POLICY IF EXISTS "Read attendance" ON attendance;
DROP POLICY IF EXISTS "Read all sessions" ON sessions;
DROP POLICY IF EXISTS "Teachers can insert sessions" ON sessions;
DROP POLICY IF EXISTS "Anyone can update sessions" ON sessions;
DROP POLICY IF EXISTS "Read anomalies" ON anomalies;
DROP POLICY IF EXISTS "Insert anomalies" ON anomalies;
DROP POLICY IF EXISTS "Read rssi_streams" ON rssi_streams;

-- =============================================
-- Recreate ALL policies (permissive)
-- =============================================

-- STUDENTS
CREATE POLICY "students_select" ON students FOR SELECT USING (true);
CREATE POLICY "students_insert" ON students FOR INSERT WITH CHECK (true);
CREATE POLICY "students_update" ON students FOR UPDATE USING (true);

-- TEACHERS
CREATE POLICY "teachers_select" ON teachers FOR SELECT USING (true);
CREATE POLICY "teachers_insert" ON teachers FOR INSERT WITH CHECK (true);
CREATE POLICY "teachers_update" ON teachers FOR UPDATE USING (true);

-- ROOMS
CREATE POLICY "rooms_select" ON rooms FOR SELECT USING (true);

-- CLASSES
CREATE POLICY "classes_select" ON classes FOR SELECT USING (true);
CREATE POLICY "classes_insert" ON classes FOR INSERT WITH CHECK (true);

-- SESSIONS (all operations needed by teacher + student apps)
CREATE POLICY "sessions_select" ON sessions FOR SELECT USING (true);
CREATE POLICY "sessions_insert" ON sessions FOR INSERT WITH CHECK (true);
CREATE POLICY "sessions_update" ON sessions FOR UPDATE USING (true);

-- ATTENDANCE
CREATE POLICY "attendance_select" ON attendance FOR SELECT USING (true);
CREATE POLICY "attendance_insert" ON attendance FOR INSERT WITH CHECK (true);
CREATE POLICY "attendance_update" ON attendance FOR UPDATE USING (true);

-- RSSI_STREAMS
CREATE POLICY "rssi_select" ON rssi_streams FOR SELECT USING (true);
CREATE POLICY "rssi_insert" ON rssi_streams FOR INSERT WITH CHECK (true);
CREATE POLICY "rssi_update" ON rssi_streams FOR UPDATE USING (true);

-- ANOMALIES
CREATE POLICY "anomalies_select" ON anomalies FOR SELECT USING (true);
CREATE POLICY "anomalies_insert" ON anomalies FOR INSERT WITH CHECK (true);
CREATE POLICY "anomalies_update" ON anomalies FOR UPDATE USING (true);
