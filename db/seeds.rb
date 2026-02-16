# frozen_string_literal: true
puts "Cleaning database..."
[Activity, EngagementScore, Prediction, Student, Cohort].each(&:delete_all)

puts "Creating 6 cohorts..."
cohort_names = [
  "PS-ENG-2024-Fall", "PS-CW-2024-Fall", "PS-PS-2024-Fall",
  "PS-ENG-2024-Sum", "PS-CW-2024-Sum", "PS-PS-2024-Sum"
]
first_names = %w[Aarav Aisha Arjun Diya Ishaan Kavya Krish Maya Nisha Pranav Riya Rohan Saanvi Tanvi Vivaan Zara]
last_names  = %w[Agarwal Bansal Chopra Desai Gupta Iyer Joshi Kapoor Kumar Mehta Nair Patel Reddy Sharma]

cohorts = cohort_names.map do |name|
  Cohort.create!(name: name, program: name.split('-')[1], instructor_name: [first_names.sample, last_names.sample].join(" "))
end

puts "Creating 150 students..."
students_to_insert = []
150.times do
  first = first_names.sample
  last  = last_names.sample
  students_to_insert << {
    cohort_id: cohorts.sample.id,
    name: "#{first} #{last}",
    email: "#{first.downcase}.#{last.downcase}#{rand(10000)}@planetspark.in",
    created_at: Time.current, updated_at: Time.current
  }
end
Student.insert_all(students_to_insert)
students = Student.all.order(:id).to_a

puts "Generating realistic activities for high-performing program..."

# Generate data from 3 months ago to current date
# Generate data from 3 months ago to current date
data_start_date = 3.months.ago.beginning_of_month.to_date
data_end_date = Date.current
total_weeks = ((data_end_date - data_start_date) / 7).ceil

puts "Generating #{total_weeks} weeks of data (from #{data_start_date} to #{data_end_date})..."

start_date = data_start_date.beginning_of_week
activities = []

# Load Simulator
simulator = StudentSimulator.new(total_weeks)

students.each_with_index do |student, index|
  persona = simulator.assign_persona(index, students.size)
  
  # Personal characteristics (each student is unique)
  specs = {
    personal_trend: rand(-0.08..0.08),           # Some improve, some decline
    boost_weeks: (0...total_weeks).to_a.sample(rand(1..3)),  # Random good weeks
    rough_weeks: (0...total_weeks).to_a.sample(rand(0..2))   # Random bad weeks
  }
  
  # Some students are "weekend warriors" vs "last-minute larrys"
  assignment_style = [:early_bird, :steady, :procrastinator].sample
  
  total_weeks.times do |week_num|
    week_start = start_date + week_num.weeks
    
    # Skip if this week is beyond our data end date
    break if week_start > data_end_date
    
    # === GENERATE ACTIVITIES USING SIMULATOR ===
    activities_count = simulator.simulate_week(persona, week_num, specs)
    
    # === ATTRIBUTE TIMESTAMPS ===
    # The simulator gives us counts, we need to create the DB records with realistic timestamps
    
    activities_count.each do |type, count|
      count.times do
        day_offset = case type
        when 'class_attended'
          [1, 3, 5].sample  # Mon, Wed, Fri
        when 'assignment_submitted'
          case assignment_style
          when :early_bird then [2, 3, 4].sample
          when :steady then [3, 4, 5].sample
          when :procrastinator then [5, 6].sample
          end
        when 'quiz_taken'
          5  # Friday quiz
        when 'question_asked'
          [1, 2, 3, 4, 5].sample  # Weekdays
        when 'parent_login'
          [0, 5, 6].sample  # Weekends mostly
        end
        
        # Apply daily energy pattern (simulation override)
        energy_by_day = { 0 => 0.9, 1 => 1.1, 2 => 1.0, 3 => 1.0, 4 => 0.95, 5 => 0.85, 6 => 0.9 }
        day_energy = energy_by_day[day_offset]
        next if rand > day_energy
        
        # Time of day varies by activity
        hour = case type
        when 'class_attended' then rand(9..11)
        when 'assignment_submitted' then rand(16..22)
        when 'quiz_taken' then rand(14..16)
        when 'question_asked' then rand(10..20)
        when 'parent_login' then rand(19..22)
        end
        
        activity_timestamp = week_start + day_offset.days + hour.hours + rand(60).minutes
        
        # Only create activity if it's not in the future
        next if activity_timestamp > Time.current
        
        activities << {
          student_id: student.id,
          activity_type: type,
          created_at: activity_timestamp
        }
      end
    end
    
    if activities.size >= 5000
      Activity.insert_all(activities)
      activities.clear
    end
  end
end

Activity.insert_all(activities) if activities.any?

puts "Calculating scores and running ML..."
EngagementScore.generate_for(Student.all, weeks_back: total_weeks)
Prediction.generate_for(Student.all, months_back: 3)

puts "✓ Seeding complete - High-performing program with realistic variance"
puts "  Data range: #{data_start_date} to #{data_end_date} (#{total_weeks} weeks)"
puts "  Expected average: ~80-85% (early weeks), ~75-80% (recent weeks)"
puts "  Distribution: 40% stars, 35% engaged, 15% moderate, 7% inconsistent, 3% disengaged"
