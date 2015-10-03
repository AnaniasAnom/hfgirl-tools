require './model.rb'

class Deck
  attr_accessor :name
  attr_reader :leaderId, :attackerIds, :defenderIds
  
  def initialize(l, as, ds)
    @name = "new deck"
    
    @leaderId = l
    @attackerIds = as
    @defenderIds = ds
    
    @leader = nil
    @attackers = Array.new(4)
    @defenders = Array.new(4)

    dups = dupcheck
    raise "Duplicate card #{dups}" if dups
  end

  def self.exists?(db, deckname)
    self.deckstate(db, deckname) != nil
  end
  def self.deckstate(db, deckname)
    db.get_first_value( "select id from deckstate ds inner join (select max(version) latest from deckstate where deck = ?) on ds.version = latest where deck = ?", [ deckname, deckname ] )
  end
    
  def self.from_db(db, deckname)
    contents = [ nil, [], [] ]
    
    deckstate = db.get_first_value( "select id from deckstate ds inner join (select max(version) latest from deckstate where deck = ?) on ds.version = latest where deck = ?", [ deckname.to_s, deckname.to_s ] )
    return nil unless deckstate
    
    db.execute( "select card, role, position from deploymentstate where deckstate = ?", [ deckstate ] ) do |row|
      case row[1]
      when 'L'
        contents[0] = row[0]
      when 'A'
        contents[1][ row[2]-1 ] = row[0]
      when 'D'
        contents[2][ row[2]-1 ] = row[0]
      else
        raise "invalid deck role for card #{row[0]} in deck #{deckname} : #{row[1]}"
      end
    end
    result = Deck.new(*contents)
    result.name = deckname
    result.loadcards(db)
  end

  def dupcheck
    [ @attackerIds, @defenderIds ].each do |deck|
      check = deck.sort
      check.each_with_index { |x,i| return x if (i>0 && x == check[i-1]) }
      return @leaderId if deck.include? @leaderId
    end
    false
  end    

  def get(db, card)
    result = Cardstate.new({ "card" => card })
    if result.fetch(db) then
      result
    else
      raise "missing card #{card}"
    end
  end

  def loadcards(db)
    @leader = get(db, @leaderId)
    @attackers = @attackerIds.map { |i| get(db, i) }
    @defenders = @defenderIds.map { |i| get(db, i) }

    self
  end

  def card_role(card)
    case
    when @leaderId == card
      'L'
    when @attackerIds.include?(card)
      'A'
    when @defenderIds.include?(card)
      'D'
    else
      nil
    end
  end

  def coord_a?
    attrib = @leader["attribute"]
    ! @attackers.any? { |c| c["attribute"] != attrib }
  end

  def memberIds
    [ @leaderId ] + @attackerIds + @defenderIds
  end

  def attack
    @attackers.inject( @leader["attack"] ) do |tot, attacker|
      tot + attacker["attack"]
    end
  end
  def defense
    @defenders.inject( @leader["defense"] ) do |tot, card|
      tot + card["defense"]
    end
  end

  def to_s
    [ [ @leader["card"] ], @attackers.map { |x| x["card"] }.join(','), @defenders.map { |x| x["card"] }.join(',') ].join(':')
  end

  def full_info
    "Leader:\n#{@leader.pretty}\n" +
      ( @attackers.map.with_index { |c, i| "Attacker #{i+1}:\n#{c.pretty}" } ).join +
      "\n" +
      ( @defenders.map.with_index { |c, i| "Defender #{i+1}:\n#{c.pretty}" } ).join +
      "\nAttack Strength: #{attack}\nDefense Strength #{defense}\n" +
      if coord_a? then
        "Coordinated #{Model.normalize_attribute(@leader["attribute"])}"
      else "Not Coordinated"
      end + "\n"
  end
    
  def set_as(db, deckname)
    @name = deckname
    dbrow = db.get_first_row( "select id, version from deckstate inner join (select max(version) latest, deck d from deckstate ds group by deck) on deckstate.deck = d and deckstate.version = latest where deck = ?", [ deckname.to_s ] )
    if dbrow then
      oldid = dbrow[0]
      version = dbrow[1] + 1
    else
      oldid = nil
      version = 1
    end
    db.transaction do 
      db.execute( "insert into deckstate (deck, version) values ( ?, ?)", [ deckname, version ] );
      deckstate = db.last_insert_row_id

      deploystmt = db.prepare( "insert into deploymentstate (card, deckstate, role, position) values (?,?,?,?)" );
      deploystmt.execute( @leaderId, deckstate, 'L', nil )
      @attackerIds.each_with_index { |card,i| deploystmt.execute( card, deckstate, 'A', i+1 ) }
      @defenderIds.each_with_index { |card,i| deploystmt.execute( card, deckstate, 'D', i+1 ) }
      deploystmt.close
      
      db.execute( "insert into decktransition( oldstate, newstate, timestamp )
                 values ( ?, ?, Datetime('now') )",
                  [ oldid, deckstate ] );
    end
  end
end
