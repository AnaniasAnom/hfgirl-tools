require 'sqlite3'
require './model.rb'
require 'rglpk.rb'

class Optimiser
  attr_accessor :size
  
  def initialize(arg)
    @size = 5
    
    if arg.instance_of? Array then
      @source = :literal
      @cards = arg
    else
      @source = arg
      @cards = []
    end
    @mode = "attack"
    @strength = 100
  end

  attr_accessor :mode, :strength

  def fetch(db)
    @cards = Model.do_search(db, @source) unless @source == :literal
  end
    
  def greedy5
    @cards.sort { |a,b| b[mode] <=> a[mode] }[0,@size]
  end

  def greedyN
    sorted = @cards.sort { |a,b| (b[mode]/b["cost"])<=>(a[mode]/a["cost"]) }
    i = 0; cost = 0
    while (( i < sorted.length ) && cost < strength ) do
      cost = cost + sorted[i]["cost"]
      i = i + 1
    end
    sorted[0,i]
  end

  def describe_candidate(arr)
    arr.each { |card| puts card.pretty }
    puts "Total strength: #{arr.inject(0) { |m,c| m + c[mode] }}"
    puts "Total cost:     #{arr.inject(0) { |m,c| m + c["cost"] }}"
  end

  def dump
    puts "Strongest #{size} cards\n"
    describe_candidate(greedy5)
    puts "Max power\n"
    describe_candidate(greedyN)
  end


  def execute_glpk(overlap_with = [])
    p = prepare_problem

    row1data = @cards.map { |c| c["cost"] }
    row2data = Array.new( @cards.length, 1 )
    row3data = []
    unless overlap_with.empty? then
      row3data = add_overlap(p, overlap_with)
    end

    p.set_matrix( row1data + row2data + row3data )
    p.mip( { :presolve => Rglpk::GLP_ON,
             :br_tech => Rglpk::GLP_BR_DTH,
             :pp_tech => Rglpk::GLP_PP_ALL,
             :binarize => Rglpk::GLP_ON } )

    @cards.zip(p.cols).reject { |p| p[1].mip_val == 0 }.map { |p| p[0] }
  end

  # This handles the requirement that a selection of 5 defense cards
  # must share one leader card with the 5 attack cards (passed in target)
  # It adds a row to the problem definition, and returns the values to
  # use for that row
  def add_overlap(problem, target)
    row = problem.add_row
    row.name = "overlap"
    row.set_bounds(Rglpk::GLP_LO, 1, 0)
    @cards.map { |c| if target.include?(c) then 1 else 0 end }
  end
    
  def prepare_problem
    p = Rglpk::Problem.new
    p.name = "deck"
    p.obj.dir = Rglpk::GLP_MAX

    rows = p.add_rows(2)
    rows[0].name = "cost"
    rows[0].set_bounds(Rglpk::GLP_UP, 0, strength)
    rows[1].name = "count"
#    rows[1].set_bounds(Rglpk::GLP_UP, 0, 5)
    rows[1].set_bounds(Rglpk::GLP_FX, size, size)

    cols = p.add_cols(@cards.length)
    @cards.each_with_index do |card,i|
      cols[i].name = card["card"].to_s
      cols[i].kind = Rglpk::GLP_BV
    end

    p.obj.coefs = @cards.map { |c| c[mode] }
    p
  end

  def to_gmpl
<<-END
set C, dimen 4;

set J := setof{ (n, c, o, v) in C} n;

var a{J}, binary;

maximize obj :
  sum{(n,c,o,v) in C} v*a[n];

s.t. cost :
  sum{(n,c,o,v) in C} c*a[n] <= #{@strength};
s.t. count :
  sum{(n,c,o,v) in C} o*a[n] <= 5;

solve;

printf{(n,c,o,v) in C: a[n] == 1 } " %i", n;
printf("\\n");

data;

set C :=
#{ (@cards.map { |c| [c["card"], c["cost"], 1, c[mode]].join(" ") }).join("\n") };

end;
END
  end
  
  def self.demo
    search = Search.new
    SQLite3::Database.new("cards.db") do |db|
      me = Optimiser.new(search)
      me.strength = 63
      me.fetch(db)
      #puts me.to_gmpl
      result = me.execute_glpk
      result.each { |c| puts c.pretty }
      print "Total #{me.mode}: "
      puts result.map { |c| c[me.mode] }.inject(:+)
    end
  end
end

#Optimiser.demo
