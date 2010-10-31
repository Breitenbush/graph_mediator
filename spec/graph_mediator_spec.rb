require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

create_schema do |conn|
  conn.create_table(:foos, :force => true) do |t|
    t.string :foo
    t.integer :lock_version, :default => 0
    t.timestamps
  end

  conn.create_table(:bars, :force => true) do |t|
    t.string :bar
    t.integer :lock_version, :default => 0
    t.timestamps
  end
  
  conn.create_table(:things, :force => true) do |t|
    t.string :name
    t.integer :lock_version, :default => 0
    t.timestamps
  end

  conn.create_table(:untimestamped_things, :force => true) do |t|
    t.string :name
    t.integer :lock_version, :default => 0
  end

  conn.create_table(:unlocked_things, :force => true) do |t|
    t.string :name
    t.timestamps
  end

  conn.create_table(:plain_things, :force => true) do |t|
    t.string :name
  end
end

class Foo < ActiveRecord::Base
  include GraphMediator
end

class UntimestampedThing < ActiveRecord::Base
  include GraphMediator
end

class UnlockedThing < ActiveRecord::Base
  include GraphMediator
end

class PlainThing < ActiveRecord::Base
  include GraphMediator
end

describe "GraphMediator" do

  it "should provide a module attribute accessor for turning mediation on or off" do
    GraphMediator.enable_mediation.should == true
    GraphMediator.enable_mediation = false
    GraphMediator.enable_mediation.should == false
  end

  it "should be able to disable and enable mediation globally"

  it "should insert a MediatorProxy class when included" do
    Foo::MediatorProxy.should include(GraphMediator::Proxy)
    Foo.should include(Foo::MediatorProxy)
  end

  it "should provide the mediate class macro" do
    Foo.should respond_to(:mediate) 
  end

  it "should provide the mediate_reconciles class macro" do
    Foo.should respond_to(:mediate_reconciles)
  end

  it "should provide the mediate_caches class macro" do
    Foo.should respond_to(:mediate_caches)
  end

  context "with a fresh class" do
  
    def load_bar
      c = Class.new(ActiveRecord::Base)
      Object.const_set(:Bar, c)
      c.__send__(:include, GraphMediator)
    end

    before(:each) do
      load_bar
    end

    after(:each) do
      Object.__send__(:remove_const, :Bar)
    end

    it "should get the when_reconciling option" do
#      Bar.__graph_mediator_reconciliation_callbacks.should == []
      Bar.mediate :when_reconciling => :foo
      Bar.mediate_reconciles_callback_chain.should == [:foo]
#      Bar.__graph_mediator_reconciliation_callbacks.size.should == 1
#      Bar.__graph_mediator_reconciliation_callbacks.first.should be_kind_of(Proc)
    end
 
    it "should collect methods through mediate_reconciles" do
#      Bar.__graph_mediator_reconciliation_callbacks.should == []
      Bar.mediate :when_reconciling => [:foo, :bar]
      Bar.mediate_reconciles :baz do
        biscuit
      end
      Bar.mediate_reconciles_callback_chain.should include(:foo, :bar, :baz)
      Bar.mediate_reconciles_callback_chain.should have(4).elements
#      Bar.__graph_mediator_reconciliation_callbacks.should have3
#      Bar.__graph_mediator_reconciliation_callbacks.each { |e| e.should be_kind_of(Proc) }
    end
 
    it "should get the when_cacheing option" do
      Bar.mediate :when_cacheing => :foo
      Bar.mediate_caches_callback_chain.should == [:foo]
    end
  
    it "should collect methods through mediate_caches" do
      Bar.mediate :when_cacheing => [:foo, :bar]
      Bar.mediate_caches :baz do
        biscuit
      end
      Bar.mediate_caches_callback_chain.should include(:foo, :bar, :baz)
      Bar.mediate_caches_callback_chain.should have(4).elements
    end
 
    it "should get the dependencies option" do
      begin
        class ::Child < ActiveRecord::Base; end
        Bar.mediate :dependencies => Child
      ensure
        Object.__send__(:remove_const, :Child) 
      end
    end

  end

  context "with a defined mediation" do 

    def load_thing
      # make sure we record all callback calls regardless of which instance we're in.
      @things_callbacks = callbacks_ref = []
      c = Class.new(ActiveRecord::Base)
      Object.const_set(:Thing, c)
      c.class_eval do
        include GraphMediator
         
        mediate :when_reconciling => :reconcile, :when_cacheing => :cache
        before_mediation :before
     
        def before; callbacks << :before; end
        def reconcile; callbacks << :reconcile; end
        def cache; callbacks << :cache; end
        define_method(:callbacks) { callbacks_ref }
      end
    end

    before(:each) do
      load_thing
      @t = Thing.new(:name => :gizmo)
    end

    after(:each) do
      Object.__send__(:remove_const, :Thing)
    end

    it "should be able to disable and enable mediation for the whole class" do
      Thing.disable_all_mediation!
      @t.save
      @t.save!
      @things_callbacks.should == []
      Thing.enable_all_mediation!
      @t.save
      @t.save!
      @things_callbacks.should == [:before, :reconcile, :cache, :before, :reconcile, :cache,]
    end

    it "should disable and enable mediation for an instance" do
      @t.disable_mediation!
      @t.save
      @t.save!
      @things_callbacks.should == []
      @t.enable_mediation!
      @t.save
      @t.save!
      @things_callbacks.should == [:before, :reconcile, :cache, :before, :reconcile, :cache,]
    end

    it "should have save_without_mediation convenience methods" do
      @t.save_without_mediation
      @t.save_without_mediation!
      @things_callbacks.should == []
    end

    it "should handle saving a new record" do
      n = Thing.new(:name => 'new')
      n.save!
      @things_callbacks.should == [:before, :reconcile, :cache,]
    end

    it "should handle updating an existing record" do
      e = Thing.create!(:name => 'exists')
      @things_callbacks.clear
      e.save!
      @things_callbacks.should == [:before, :reconcile, :cache,]
    end

    it "should nest mediated transactions" do
      Thing.class_eval do
        after_create do |instance|
          instance.mediated_transaction do
            instance.callbacks << :nested_create!
          end
        end
        after_save do |instance|
          instance.mediated_transaction do
            instance.callbacks << :nested_save!
          end
        end
      end
      nested = Thing.create!(:name => :nested!)
      @things_callbacks.should == [:before, :nested_create!, :nested_save!, :reconcile, :cache, :nested_save!]
      # The final nested save is the touch and lock_version bump
    end

    # can't nest before_create.  The second mediated_transaction will occur
    # before instance has an id, so we have no way to look up a mediator.
    it "cannot nest mediated transactions before_create if versioning" do
      Thing.class_eval do
        before_create do |instance|
          instance.mediated_transaction do
            instance.callbacks << :nested_before_create!
          end
        end
      end
      lambda { nested = Thing.create!(:name => :nested!) }.should raise_error(GraphMediator::MediatorException)
      #@things_callbacks.should == [:before, :before, :nested_before_create!, :reconcile, :cache, :reconcile, :cache,]
    end

    it "should override save" do
      @t.save
      @things_callbacks.should == [:before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should override save bang" do
      @t.save!
      @things_callbacks.should == [:before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should allow me to override save locally" do
      Thing.class_eval do
        def save
          callbacks << '...saving...'
          super
        end
      end
      @t.save
      @things_callbacks.should == ['...saving...', :before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should allow me to decorate save_with_mediation" do
      Thing.class_eval do
        alias_method :save_without_transactions_with_mediation_without_logging, :save_without_transactions_with_mediation
        def save_without_transactions_with_mediation(*args)
          callbacks << '...saving...'
          save_without_transactions_with_mediation_without_logging(*args)
        end
      end
      @t.save
      @things_callbacks.should == ['...saving...', :before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should allow me to decorate save_without_mediation" do
      Thing.class_eval do
        alias_method :save_without_transactions_without_mediation_without_logging, :save_without_transactions_without_mediation
        def save_without_transactions_without_mediation(*args)
          callbacks << '...saving...'
          save_without_transactions_without_mediation_without_logging(*args)
        end
      end
      @t.save
      @things_callbacks.should == [:before, '...saving...', :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

  end

  context "with an instance" do

    before(:each) do
      @f = Foo.new
    end

    it "cannot update lock_version without timestamps" do
      t = UntimestampedThing.create!(:name => 'one')
      t.lock_version.should == 0
      t.touch
      t.lock_version.should == 0
      t.mediated_transaction {}
      t.lock_version.should == 0
    end

    it "should update lock_version on touch if instance has timestamps" do
      @f.save!
      @f.lock_version.should == 1
      @f.touch
      @f.lock_version.should == 2
    end

    it "should get a mediator" do
      begin 
        mediator = @f.__send__(:_get_mediator)
        mediator.should be_kind_of(GraphMediator::Mediator)
        mediator.mediated_instance.should == @f 
      ensure
        @f.__send__(:mediators_for_new_records).clear
      end
    end

    it "should always get a new mediator for a new record" do
      begin
        @f.new_record?.should be_true
        mediator1 = @f.__send__(:_get_mediator)
        mediator2 = @f.__send__(:_get_mediator)
        mediator1.should_not equal(mediator2)
      ensure
        @f.__send__(:mediators_for_new_records).clear
      end
    end

    it "should get the same mediator for a saved record" do
      begin
        @f.save_without_mediation
        @f.new_record?.should be_false
        mediator1 = @f.__send__(:_get_mediator)
        mediator2 = @f.__send__(:_get_mediator)
        mediator1.should equal(mediator2)
      ensure
        @f.__send__(:mediators).clear
      end
    end

    # @f.create -> calls save, which engages mediation on a new record which has no id.
    # During the creation process (after_create) @f will have an id.
    # Other callbacks may create dependent objects, which will attempt to mediate, or
    # other mediated methods, and these should receive the original mediator if we have
    # reached after_create stage.
    it "should get the same mediator for a new record that is saved during mediation" do
      begin
        @f.new_record?.should be_true
        mediator1 = @f.__send__(:_get_mediator)
        @f.save_without_mediation
        mediator2 = @f.__send__(:_get_mediator)
        mediator1.should equal(mediator2)
      ensure
        @f.__send__(:mediators_for_new_records).clear
        @f.__send__(:mediators).clear
      end
    end

    it "should indicate if currently mediating for a new instance" do
      @f.currently_mediating?.should be_false
      @f.mediated_transaction do
        @f.currently_mediating?.should be_true
      end
    end

    it "should indicate if currently mediating for an existing instance" do
      @f.save!
      @f.currently_mediating?.should be_false
      @f.mediated_transaction do
        @f.currently_mediating?.should be_true
      end
    end

    it "should expose the current phase of mediation" do
      @f.current_mediation_phase.should be_nil
      @f.mediated_transaction do
        @f.current_mediation_phase.should == :mediating
      end
      @f.save!
      @f.current_mediation_phase.should be_nil
      @f.mediated_transaction do
        @f.current_mediation_phase.should == :mediating
      end
    end

# TODO - may need to move this up to the class

    it "should generate a unique mediator_hash_key for each MediatorProxy" do
      @f.class.mediator_hash_key.should == 'GRAPH_MEDIATOR_FOO_HASH_KEY'
    end

    it "should generate a unique mediator_new_array_key for each MediatorProxy" do
      @f.class.mediator_new_array_key.should == 'GRAPH_MEDIATOR_FOO_NEW_ARRAY_KEY'
    end
 
    it "should access an array of mediators for new records" do
      @f.__send__(:mediators_for_new_records).should == []
    end

    it "should access a hash of mediators" do
      @f.__send__(:mediators).should == {}
    end

  end
end
