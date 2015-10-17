class Models
  def initialize
    @fields = %w(id card version name rarity trained level attribute cost attack defense affection tags skillrefs season live)
    @mandatory = %w(name attribute cost attack defense)
    @constant = %w(card version name attribute tags skillrefs season)
    @counters = %w(cardcounter transitioncounter)
    @attributes = %w(Lady Teen Chick Madame -)
    @rarities = %w(Common UnCommon Rare SuperRare UltraRare Legendary Ultimate)
    @roles = %w(Leader Attacker Defender)
  end
  
  attr_reader :fields, :mandatory, :constant, :counters, :attributes, :rarities, :roles
  
  def search(db, searchstr, values = [])
    base = "select #{fields.join(",")} from cardstate cards inner join (select card c, max(version) last 
from cardstate cs group by card) on cards.card = c and cards.version = last "
    query = base + searchstr
    result = []
    db.execute( query, values ) do |row|
      result.push( Cardstate.new({}).populate(row) )
    end
    result
  end

  def history(db, card)
    base = "select c.#{fields.join(", c.")}, c.id, t.transition, c.version, t.timestamp, t.transitiontype, t.role from cardstate c inner join cardtransition t on c.id = t.cardstate where c.card = ? order by c.version"
    db.execute(base, [card]).map do |state|
      card_params = fields.zip(state).to_h
      transition_params = state.last(5)
      { :transition => transition_params[0],
        :version => transition_params[1],
        :timestamp => transition_params[2],
        :action => transition_params[3],
        :role => transition_params[4],
        :state => Cardstate.new(card_params) }
    end
  end    

  def do_search(db, params)
    search(db, params.to_s, params.values)
  end

  def normalize(string, list)
    up = string.upcase
    short = ( string.length == 1 )
    list.each do |item|
      if short then
        return item if ( up == item[0] )
      else
        return item if ( up == item.upcase )
      end
    end
    nil
  end
  
  def normalize_attribute(string)
    normalize(string, attributes)
  end

  def normalize_rarity(string)
    return string if string.to_i > 0
    up = string.upcase
    
    i = @rarities.find_index { |r| r.upcase == up }
    i && i+1
  end

  def normalize_role(string)
    normalize(string, roles)
  end

  def current_decks(db)
    (1..5).map do |d|
      Deck.from_db(db, d.to_s)
    end.reject(&:nil?)
  end
end
Model = Models.new

class Cardstate

  attr_accessor :source
  
  def initialize(values_in)
    @values = {}
    values_in.each_pair do |k,v|
      unless set(k, v) then
        raise "invalid field #{k}"
      end
    end
    @source = ""
  end
  
  def set(field, value)
    if ( Model.fields.include?(field) ) then
      if field == "attribute" then
        norm_value = Model.normalize_attribute(value)[0]
        raise "invalid attribute #{value}" unless norm_value
      elsif field == "rarity" then
        norm_value = Model.normalize_rarity(value)
      else
        norm_value = value
      end
      
      @values[field] = norm_value
      true
    else
      nil
    end
  end

  def [](field)
    if ( Model.fields.include?(field) ) then
      @values[field]
    else
      nil
    end
  end

  def valid?
    Model.mandatory.each do |field|
      return false if ( ! @values.has_key?(field) )
    end
    true
  end

  def missing_fields
    Model.mandatory.reject { |f| @values.has_key? f }
  end

  def live?
    self["live"] == 1
  end
  
  def buildStatement
    data = { :names => [], :placeholders => [], :values => [] }
    Model.fields.each do |field|
      if field != "id" then
        if @values.has_key? field then
          data[:names].push field
          data[:placeholders].push "?"
          data[:values].push @values[field]
        end
      end
    end
    data
  end
  
  def save
    if @values.has_key? "card" then
      raise "cannot add a card that is already in db"
    else
      save_new
    end
  end

  def insert_cardstate(db)
    insert = buildStatement
    statement = "insert into cardstate ( #{insert[:names].join(",")} ) values ( #{insert[:placeholders].join(",")} )"
    db.execute(statement, insert[:values])
    @values["id"] = db.last_insert_row_id
  end

  def get_counter(db, counter)
    raise Exception.new "bad counter #{counter}" unless Model.counters.include? counter
    db.execute("update globals set #{counter} = #{counter}+1");
    (result, @timestamp) = db.get_first_row("select #{counter}, datetime('now') from globals");
    result
  end
  
  def save_new
    return false unless valid?
    transitiontype = source || 'create'
    
    SQLite3::Database.new( DATABASE ) do |db|
      db.transaction do
        @values["card"] = get_counter(db, "cardcounter")
        insert_cardstate(db)
        @values["version"] = 1

        transition = get_counter(db, "transitioncounter")
        db.execute("insert into cardtransition (transition, cardstate, role, transitiontype, timestamp)
values (?, ?, 'result', ?, datetime('now'))", [ transition, @values["id"], transitiontype ])
      end
    end
  end

  def populate(dbrow)
    Model.fields.each do |field|
      val = dbrow.shift
      @values[field] = val unless val == nil
    end
    self
  end
  
  def fetch(db)
    row = db.get_first_row("select #{Model.fields.join(",")}, max(version) ver from cardstate 
                            group by card
                            having card = ? and version = ver",
                           [@values["card"]])
    Model.fields.each do |field|
      val = row.shift
      @values[field] = val unless val == nil
    end
    self
  end

  def load
    SQLite3::Database.new( DATABASE ) do |db|
      fetch(db)
    end
  end

  def pretty( tags = false )
    stars = "%-6s" % ("\u2605"*self["rarity"]+"+"*self["trained"])
    if live?
      if tags then extra = "Tags: #{self["tags"]}\n" else extra = "" end
      "%3d. %s \033[1m%s\033[0m\nLvl %-3d %-6s Cost: %2d  Attack %4d Defense %4d\n%s" %
        [ self["card"], stars, self["name"], self["level"], Model.normalize_attribute(self["attribute"]),
          self["cost"], self["attack"], self["defense"], extra ] 
    else
      "Dead card %3d. %s %s\n" % [ self["card"], stars, self["name"] ]
    end
  end

  def to_s
    result = "Cardstate:\n"
    Model.fields.each do |field|
      value = @values[field]
      if field == "attribute" then
        norm_value = Model.normalize_attribute value
      elsif field == "rarity" then
        if self["trained"] > 0 then norm_value = "#{value}+" else norm_value = value end
      else
        norm_value = value
      end
      result = result.concat " #{field}\t#{norm_value}\n"
    end
    result
  end

  def insert_transition(db, transition, oldstate, cardstate, role, transitiontype, timestamp)
    db.execute("insert into cardtransition (transition, oldstate, cardstate, role, transitiontype, timestamp)
                values (?, ?, ?, ?, ?, ?)",
               [transition, oldstate, cardstate, role, transitiontype, timestamp])
  end

  def remove(db, transition, role, transitiontype, timestamp)
    old_id = self["id"]
    old_version = self["version"]
    set("version", old_version+1)
    set("live", 0)
    insert_cardstate(db)
    insert_transition(db, transition, old_id, self["id"], role, transitiontype, timestamp)
  end

  def promote(new_level, new_attack, new_defense, materials)
    SQLite3::Database.new( DATABASE ) do |db|
      db.transaction do
        material_cards = materials.map do |m|
          card = Cardstate.new({"card" => m }).fetch(db)
          raise "Could not find card #{m}" unless card.valid? && card.live?
          card
        end
        
        fetch(db)
        old_id = @values["id"]
        @values["version"] = @values["version"]+1
        @values["level"] = new_level
        @values["attack"] = new_attack
        @values["defense"] = new_defense
        insert_cardstate(db)

        transition = get_counter(db, "transitioncounter")
        insert_transition(db, transition, old_id, self["id"], 'target', 'promote', @timestamp)

        material_cards.each { |m| m.remove(db, transition, 'material', 'promote', @timestamp) }
      end
    end
  end

  def affect(new_attack, new_defense)
    SQLite3::Database.new( DATABASE ) do |db|
      db.transaction do
        
        fetch(db)
        old_id = @values["id"]
        @values["version"] = @values["version"]+1
        @values["attack"] = new_attack
        @values["defense"] = new_defense
        insert_cardstate(db)

        transition = get_counter(db, "transitioncounter")
        insert_transition(db, transition, old_id, self["id"], 'target', 'affect', @timestamp)
      end
    end
  end

  def train(new_attack, new_defense, new_tags, material)
    SQLite3::Database.new( DATABASE ) do |db|
      db.transaction do
        fetch(db)

        material_card = Cardstate.new({"card" => material }).fetch(db)

        unless material_card.valid? && material_card.live?
          raise "Could not find card #{m}"
        end
        
        me = "#{self["name"]}.#{self["rarity"]}"
        it = "#{material_card["name"]}.#{material_card["rarity"]}"
        if ( me != it ) then
          raise "Mismatch in training: #{me} vs #{it}"
        end

        trained_vals = {
          "name" => self["name"],
          "rarity" => self["rarity"],
          "attribute" => self["attribute"],
          "level" => 1,
          "trained" => 1,
          "attack" => new_attack,
          "defense" => new_defense,
          "cost" => self["cost"],
          "tags" => new_tags,
          "skillrefs" => self["skillrefs"],
          "version" => 1,
          "card" => get_counter(db, "cardcounter")
        }
        new_card = Cardstate.new(trained_vals);
        new_card.insert_cardstate(db);
        new_card.fetch(db);
        
        transition = get_counter(db, "transitioncounter")
        insert_transition(db, transition, nil, new_card["id"],
                          'result', 'train', @timestamp)

        material_card.remove(db, transition, 'material', 'train', @timestamp)
        remove(db, transition, 'target', 'train', @timestamp)
      end
    end
  end

  def clear(new_attack, new_defense, material)
    SQLite3::Database.new( DATABASE ) do |db|
      db.transaction do
        fetch(db)

        material_card = Cardstate.new({"card" => material }).fetch(db)

        unless material_card.valid? && material_card.live?
          raise "Could not find card #{m}"
        end

        me = "#{self["name"]}.#{self["rarity"]}"
        it = "#{material_card["name"]}.#{material_card["rarity"]}"

        if ( self["trained"] == 0 )
          raise "Clear must be on trained card: #{me}"
        end
        
        if ( me != it ) then
          raise "Mismatch in training: #{me} vs #{it}"
        end

        trained_vals = {
          "name" => self["name"],
          "rarity" => self["rarity"],
          "attribute" => self["attribute"],
          "level" => self["level"],
          "trained" => self["trained"]+1,
          "attack" => new_attack,
          "defense" => new_defense,
          "cost" => self["cost"],
          "tags" => self["tags"],
          "version" => 1,
          "card" => get_counter(db, "cardcounter")
        }
        new_card = Cardstate.new(trained_vals);
        new_card.insert_cardstate(db);
        new_card.fetch(db);
        
        transition = get_counter(db, "transitioncounter")
        insert_transition(db, transition, nil, new_card["id"],
                          'result', 'clear', @timestamp)

        material_card.remove(db, transition, 'material', 'clear', @timestamp)
        remove(db, transition, 'target', 'clear', @timestamp)
      end
    end
  end

  def delete(db)
    transition = get_counter(db, "transitioncounter")
    remove(db, transition, 'target', 'correction', @timestamp)
  end
end

class Search
  def initialize
    @conditions = []
    @orders = []
  end

  def to_s
    where + orderby
  end
  def where
    if @conditions.empty? then
      ""
    else
      " where " + (@conditions.map { |x| x[0] }).join( " and " )
    end
  end
  def orderby
    if @orders.empty? then
      ""
    else
      " order by " + @orders.join( ", " )
    end
  end

  def values
    @conditions.map { |x| x[1] }
  end
  
  def checkfield(f)
    raise "invalid field #{f}" unless Model.fields.include? f
  end
  
  def above(field, value)
    checkfield field
    @conditions.push( [ "#{field} > ?", value ] )
    self
  end
  def below(field, value)
    checkfield field
    @conditions.push( [ "#{field} < ?", value ] )
    self
  end
  def match(field, value)
    checkfield field
    db_value = if field == "attribute" then
                 attr = Model.normalize_attribute(value)
                 raise "invalid attribute #{value}" unless attr
                 attr[0]
               elsif field == "rarity" then
                 Model.normalize_rarity(value)
               else
                 value
               end
    @conditions.push( [ "#{field} = ?", db_value ] )
    self
  end
  def like(field, value)
    checkfield field
    @conditions.push( [ "#{field} like ?", value ] )
    self
  end

  def by(field, direction = :+)
    checkfield field
    if field == "rarity"
      expr = "(rarity*10+trained)"
    else
      expr = field
    end
    
    case direction
    when :+
      @orders.push( expr )
    when :-
      @orders.push( "#{expr} desc" )
    else
      raise "invalid direction #{direction}"
    end
    self
  end
  def byrate(field, direction = :+)
    checkfield field
    case direction
    when :+
      @orders.push( "#{field}/cost" )
    when :-
      @orders.push( "#{field}/cost desc" )
    else
      raise "invalid direction #{direction}"
    end
    self
  end
      

  def live(positive=true)
    value = if positive then 1 else 0 end
    @conditions.push( [ "live = ?", value ] )
    self
  end    
end
