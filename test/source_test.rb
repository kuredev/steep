require_relative "test_helper"

class SourceTest < Minitest::Test
  A = Steep::AST::Annotation
  T = Steep::AST::Types
  Namespace = RBS::Namespace

  include TestHelper
  include SubtypingHelper
  include FactoryHelper

  def test_foo
    with_factory do |factory|
      code = <<-EOF
# @type var x1: untyped

module Foo
  # @type var x2: untyped

  class Bar
    # @type instance: String
    # @type module: singleton(String)

    # @type var x3: untyped
    # @type method foo: -> untyped
    def foo
      # @type return: untyped
      # @type var x4: untyped
      self.tap do
        # @type var x5: untyped
        # @type block: Integer
      end
    end

    # @type method bar: () -> untyped
    def bar
    end
  end
end

Foo::Bar.new
      EOF

      source = Steep::Source.parse(code, path: Pathname("foo.rb"), factory: factory)

      # toplevel
      source.annotations(block: source.node,
                         factory: factory,
                         context: nil).yield_self do |annotations|
        assert_any annotations do |a|
          a.is_a?(A::VarType) && a.name == :x1 && a.type == T::Any.new
        end
      end

      # module
      source.annotations(block: dig(source.node, 0),
                         factory: factory,
                         context: [nil, TypeName("::Foo")]).yield_self do |annotations|
        assert_any annotations do |a|
          a == A::VarType.new(name: :x2, type: T::Any.new)
        end
        assert_nil annotations.instance_type
        assert_nil annotations.module_type
      end

      # class

      source.annotations(block: dig(source.node, 0, 1),
                         factory: factory,
                         context: [nil, TypeName("::Foo::Bar")]).yield_self do |annotations|
        assert_equal 5, annotations.size
        assert_equal parse_type("::String"), annotations.instance_type
        assert_equal parse_type("singleton(::String)"), annotations.module_type
        assert_equal parse_type("untyped"), annotations.var_type(lvar: :x3)
      end

      # def
      source.annotations(block: dig(source.node, 0, 1, 2, 0),
                         factory: factory,
                         context: [nil, TypeName("::Foo::Bar")]).yield_self do |annotations|
        assert_equal 2, annotations.size
        assert_equal T::Any.new, annotations.var_type(lvar: :x4)
        assert_equal T::Any.new, annotations.return_type
      end

      # block
      source.annotations(block: dig(source.node, 0, 1, 2, 0, 2),
                         factory: factory,
                         context: [nil, TypeName("::Foo::Bar")]).yield_self do |annotations|
        assert_equal 2, annotations.size
        assert_equal T::Any.new, annotations.var_type(lvar: :x5)
        assert_equal parse_type("::Integer"), annotations.block_type
      end
    end
  end

  def test_if
    with_factory do |factory|
      code = <<-EOF
if foo
  # @type var x: String
  x + "foo"
else
  # @type var y: Integer
  y + "foo"
end
      EOF
      source = Steep::Source.parse(code, path: Pathname("foo.rb"), factory: factory)

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[2].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_unless
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
unless foo then
  # @type var x: Integer
  x + 1
else
  # @type var y: String
  y + "foo"
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end

      source.node.children[2].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_elsif
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
if foo
  # @type var x: String
  x + "foo"
elsif bar
  # @type var y: Integer
  y + "foo"
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      dig(source.node, 1).yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      dig(source.node, 2, 1).yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_postfix_if
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x + 1 if foo
y + "foo" unless bar
      EOF

      source.annotations(block: source.node, factory: factory, context: nil)
    end
  end

  def test_if_then_else
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x = if test then 1 else 2 end
      EOF

      source.annotations(block: source.node, factory: factory, context: nil)
    end
  end

  def test_while
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
while foo
  # @type var x: Integer
  x.foo
end
      EOF
      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_until
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
until foo
  # @type var x: Integer
  x.foo
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_postfix_while_until
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x + 1 while foo
y + "foo" until bar
      EOF

      source.annotations(block: source.node, factory: factory, context: nil)
    end
  end

  def test_post_while
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
begin
  # @type var x: Integer
  x.foo
x.bar
end while foo()
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_post_until
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
begin
  # @type var x: Integer
  x.foo
x.bar
end until foo()
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_case
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
case foo
when bar
  # @type var x: String
  x+1
else
  # @type var y: Integer
  y - 1
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[1].children.last.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[2].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_empty_source
    with_factory do |factory|
      Steep::Source.parse("", path: Pathname("foo.rb"), factory: factory)
    end
  end

  def test_empty_clauses
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
case
when bar
else
end

if foo
else
end

begin
rescue
else
end
      EOF
    end
  end

  def test_rescue
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
begin
 foo
rescue Z => x
  # @type var x: String
  x+1
else
  # @type var y: Integer
  y - 1
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[0].children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[0].children.last.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, context: nil)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_postfix_rescue
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x + 1 rescue foo
    EOF

      source.annotations(block: source.node, factory: factory, context: nil)
    end
  end

  def test_ternary_operator
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
a = test() ? foo : bar
      EOF

      source.annotations(block: source.node, factory: factory, context: nil)
    end
  end

  def test_defs
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
class A
  def self.foo()
    # @type var x: Integer
    x = 123
  end
end
      EOF
      def_node = dig(source.node, 2)

      annotations = source.annotations(block: def_node, factory: factory, context: [nil, TypeName("::A")])
      assert_equal parse_type("::Integer"), annotations.var_type(lvar: :x)
    end
  end

  def test_find_node
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
class A
  def self.foo(bar)
    # @type var x: Integer
    x = 123
  end
end
      EOF

      assert_equal [source.node],
                   source.find_nodes(line: 1, column: 2)    # class
      assert_equal [dig(source.node, 0), source.node],
                   source.find_nodes(line: 1, column: 6)    # A
      assert_equal [dig(source.node, 0), source.node],
                   source.find_nodes(line: 1, column: 7)    # A
      assert_equal [dig(source.node, 2, 0), dig(source.node, 2), source.node],
                   source.find_nodes(line: 2, column: 6)    # self
      assert_equal [dig(source.node, 2), source.node],
                   source.find_nodes(line: 2, column: 11)   # def
      assert_equal [dig(source.node, 2, 2, 0), dig(source.node, 2, 2), dig(source.node, 2), source.node],
                   source.find_nodes(line: 2, column: 15)   # bar
      assert_equal [dig(source.node, 2, 3), dig(source.node, 2), source.node],
                   source.find_nodes(line: 4, column: 5)    # x
    end
  end

  def test_delete_defs
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
require "thread"

class A < X
  def foo(bar)
    x = 123
  end

  attr_reader :baz

  module B
    def self.hello
      puts :world
    end

    class <<self
      define_method :hogehoge do
        1+2
      end
    end
  end

  C = Struct.new(:x, :y) do
    def test
    end
  end
end
      EOF

      source.without_unrelated_defs(line: 5, column: 4).tap do |s|
        assert_equal parse_ruby(<<-RB).node, s.node
require "thread"

class A < X
  def foo(bar)
    x = 123
  end

  attr_reader :baz

  module B
    self

    class <<self
      define_method :hogehoge do
        1+2
      end
    end
  end

  C = Struct.new(:x, :y) do
    nil
  end
end
        RB

      end
    end
  end

  def test_delete_defs_annotation
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
class Foo
  X = Struct.new do
    # @implements Foo::X

    def hello
    end

    def world
    end
  end
end
      EOF

      source.without_unrelated_defs(line: 6, column: 0).tap do |source|
        block = dig(source.node, 2, 2)
        annots = source.annotations(block: block, factory: factory, context: nil)

        refute_nil annots.implement_module_annotation
      end
    end
  end

  def test_delete_defs_toplevel
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
class Foo
  def foo
  end
end

# @type var t: [Integer, String]
t = [10, ""]
      EOF

      source.without_unrelated_defs(line: 6, column: 0).tap do |source|
        annots = source.annotations(block: source.node, factory: factory, context: nil)

        refute_nil annots.var_type_annotations[:t]
      end
    end
  end

  def test_assertion_assignment
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x = nil #  : String?
(y = nil) #: Integer?
      EOF

      source.node.children[0].tap do |node|
        assert_equal :lvasgn, node.type
        assert_equal :assertion, node.children[1].type
      end

      source.node.children[1].tap do |node|
        assert_equal :assertion, node.type
        assert_equal :begin, node.children[0].type
      end
    end

    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
@x = nil #  : String?
@@a = nil #: Integer?
$a = nil #: Integer?
C = nil #: Integer?
x,y = [1,2] #: [Integer, Integer?]
      EOF

      source.node.children[0].tap do |node|
        assert_equal :ivasgn, node.type
        assert_equal :assertion, node.children[1].type
      end

      source.node.children[1].tap do |node|
        assert_equal :cvasgn, node.type
        assert_equal :assertion, node.children[1].type
      end

      source.node.children[2].tap do |node|
        assert_equal :gvasgn, node.type
        assert_equal :assertion, node.children[1].type
      end

      source.node.children[3].tap do |node|
        assert_equal :casgn, node.type
        assert_equal :assertion, node.children[2].type
      end

      source.node.children[4].tap do |node|
        assert_equal :masgn, node.type
        assert_equal :mlhs, node.children[0].type
        assert_equal :assertion, node.children[1].type
      end
    end
  end

  def test_assertion_voids
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
return 123 #: Integer?
break 123 #: Integer?
next 123 #: Integer?
      EOF

      source.node.children[0].tap do |node|
        assert_equal :return, node.type
        assert_equal :assertion, node.children[0].type
      end
      source.node.children[1].tap do |node|
        assert_equal :break, node.type
        assert_equal :assertion, node.children[0].type
      end
      source.node.children[2].tap do |node|
        assert_equal :next, node.type
        assert_equal :assertion, node.children[0].type
      end
    end
  end
end
