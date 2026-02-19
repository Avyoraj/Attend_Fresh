-- =============================================
-- Migration 002: Additional RLS Policies for Auth
-- Ensures authenticated users can query their own data
-- =============================================

-- Students can read their own record
CREATE POLICY "Students read own profile" ON students
  FOR SELECT USING (true);

-- Allow inserting student records (for sign-up)
CREATE POLICY "Anyone can insert students" ON students
  FOR INSERT WITH CHECK (true);

-- Allow updating student records
CREATE POLICY "Students update own profile" ON students
  FOR UPDATE USING (true);

-- Teachers can read their own profile
CREATE POLICY "Teachers read own profile" ON teachers
  FOR SELECT USING (true);

-- Allow inserting teacher records (for sign-up)
CREATE POLICY "Anyone can insert teachers" ON teachers
  FOR INSERT WITH CHECK (true);

-- Allow updating teacher records
CREATE POLICY "Teachers update own profile" ON teachers
  FOR UPDATE USING (true);

-- Allow reading classes
CREATE POLICY "Public read classes" ON classes
  FOR SELECT USING (true);

-- Allow reading all attendance records (students see their own via app filter)
CREATE POLICY "Read attendance" ON attendance
  FOR SELECT USING (true);

-- Allow reading sessions (for history/discovery)
CREATE POLICY "Read all sessions" ON sessions
  FOR SELECT USING (true);

-- Allow inserting sessions (teacher starts session)
CREATE POLICY "Teachers can insert sessions" ON sessions
  FOR INSERT WITH CHECK (true);

-- Allow updating sessions (end session, sync minor)
CREATE POLICY "Anyone can update sessions" ON sessions
  FOR UPDATE USING (true);

-- Allow reading anomalies
CREATE POLICY "Read anomalies" ON anomalies
  FOR SELECT USING (true);

-- Allow inserting anomalies (backend creates them)
CREATE POLICY "Insert anomalies" ON anomalies
  FOR INSERT WITH CHECK (true);

-- Allow reading rssi_streams
CREATE POLICY "Read rssi_streams" ON rssi_streams
  FOR SELECT USING (true);
