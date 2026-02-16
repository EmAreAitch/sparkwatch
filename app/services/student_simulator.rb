class StudentSimulator
  ACTIVITY_TYPES = ['class_attended', 'assignment_submitted', 'quiz_taken', 'question_asked', 'parent_login'].freeze
  WEEKLY_TARGETS = [3, 2, 1, 2, 2].freeze

  PERSONAS = {
    star_student: { base: 1.15, variance: 0.1, decline: 0.05 },    # 40%: Exceptional
    engaged: { base: 1.0, variance: 0.15, decline: 0.08 },          # 35%: Solid
    moderate: { base: 0.8, variance: 0.2, decline: 0.12 },          # 15%: Variable
    inconsistent: { base: 0.6, variance: 0.25, decline: 0.2 },      # 7%: Struggling
    disengaged: { base: 0.2, variance: 0.15, decline: 0.1 }         # 3%: At-risk
  }.freeze

  def initialize(total_weeks)
    @total_weeks = total_weeks
  end

  def assign_persona(index, total_students)
    percentile = (index.to_f / total_students) * 100
    case percentile
    when 0...40   then :star_student
    when 40...75  then :engaged
    when 75...90  then :moderate
    when 90...97  then :inconsistent
    else :disengaged
    end
  end

  # Returns a hash of activity counts for a specific week
  # { 'class_attended' => 3, 'assignment_submitted' => 2, ... }
  def simulate_week(persona, week_num, student_specifics = {})
    config = PERSONAS[persona]
    
    # Base rate calculation
    rate = calculate_engagement_rate(config, week_num, student_specifics)
    
    # Generate activity counts based on rate
    counts = {}
    WEEKLY_TARGETS.each_with_index do |target, idx|
      type = ACTIVITY_TYPES[idx]
      expected = target * rate
      
      actual = if expected < 0.2
        rand < expected ? 1 : 0
      else
        base = expected.floor
        base += 1 if rand < (expected - base)
        [base, (target * 1.5).to_i].min
      end
      
      counts[type] = actual
    end
    
    counts
  end

  private

  def calculate_engagement_rate(config, week_num, specs)
    rate = config[:base]
    
    # 1. Weekly variance
    rate += rand(-config[:variance]..config[:variance])
    
    # 2. Semester progression
    if @total_weeks > 0
      weeks_progress = week_num.to_f / @total_weeks
      rate -= config[:decline] * weeks_progress
      
      # 3. Personal trajectory
      rate += (specs[:personal_trend] || 0) * weeks_progress
    end

    # 4. Motivation boost
    if specs[:boost_weeks]&.include?(week_num)
      rate *= 1.3
    end

    # 5. Rough weeks
    if specs[:rough_weeks]&.include?(week_num)
      rate *= 0.5
    end

    # 6. Mid-semester slump
    mid_point = @total_weeks / 2
    if (mid_point - 1..mid_point + 1).include?(week_num)
      rate *= 0.9
    end

    # 7. Final push (or burnout)
    if week_num >= @total_weeks - 2
      # For disengaged, it's burnout (0.7), for others it's a toss-up
      if config[:base] < 0.5 # Proxy for disengaged/inconsistent
         rate *= 0.7 
      else
         rate *= (rand < 0.6 ? 1.2 : 0.95)
      end
    end

    [[rate, 0].max, 1.4].min
  end
end
