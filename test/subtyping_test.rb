require_relative "test_helper"

class SubtypingTest < Minitest::Test
  include TestHelper
  include Steep

  BUILTIN = <<-EOB
class BasicObject
end

class Object <: BasicObject
  def class: () -> class
end

class Class<'instance>
  def new: (*any, **any) -> 'instance
end

class Module
end

class String
  def to_str: -> String
  def self.try_convert: (any) -> String
end

class Integer
  def to_int: -> Integer
  def self.sqrt: (Integer) -> Integer
end

class Array<'a>
  def []: (Integer) -> 'a
  def []=: (Integer, 'a) -> 'a
end
  EOB

  def new_checker(signature)
    env = AST::Signature::Env.new

    parse_signature(BUILTIN).each do |sig|
      env.add sig
    end

    parse_signature(signature).each do |sig|
      env.add sig
    end

    builder = Interface::Builder.new(signatures: env)
    Subtyping::Check.new(builder: builder)
  end

  def test_interface
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
end

class B
  def foo: -> any
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result
  end

  def test_interface2
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
  def bar: -> any
end

class B
  def foo: -> any
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
    assert_equal :bar, result.error.name
    assert_equal [
                   [AST::Types::Name.new_instance(name: "::B"),
                    AST::Types::Name.new_instance(name: "::A")]
                 ], result.trace.array
  end

  def test_interface3
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
end

class B
  def foo: -> String
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
    assert_equal :to_str, result.error.name
  end

  def test_interface4
    checker = new_checker(<<-EOS)
class A
  def foo: () -> Integer
end

class B
  def foo: (?Integer, ?foo: Symbol) -> any
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result
  end

  def test_interface5
    checker = new_checker(<<-EOS)
class A
  def foo: <'a> () -> 'a
end

class B
  def foo: () -> Integer
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::UnknownPairError, result.error
  end

  def test_interface6
    checker = new_checker(<<-EOS)
class A
  def foo: <'a, 'b> ('a) -> 'b
end

class B
  def foo: <'x> ('x) -> Integer
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::UnknownPairError, result.error
  end

  def test_interface7
    checker = new_checker(<<-EOS)
class A
  def foo: (Integer) -> Integer
         | (any) -> any
end

class B
  def foo: (String) -> String
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
  end

  def test_interface8
    checker = new_checker(<<-EOS)
class A
  def foo: () { -> Object } -> String
end

class B
  def foo: () { -> String } -> Object
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
  end

  def test_interface9
    checker = new_checker(<<-EOS)
class A
  def foo: () { (String) -> any } -> String
end

class B
  def foo: () { (Object) -> any } -> Object
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
  end

  def test_union
    checker = new_checker(<<-EOS)
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::String"),
        super_type: AST::Types::Union.new(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                AST::Types::Name.new_instance(name: "::String")]),
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Union.new(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                AST::Types::Name.new_instance(name: "::Integer")]),
        super_type: AST::Types::Name.new_instance(name: "::String")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_equal 1, result.trace.size

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::Integer"),
        super_type: AST::Types::Union.new(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                  AST::Types::Name.new_instance(name: "::BasicObject")]),
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::Integer"),
        super_type: AST::Types::Union.new(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                  AST::Types::Name.new_instance(name: "::String")]),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result
  end

  def test_intersection
    checker = new_checker(<<-EOS)
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::String"),
        super_type: AST::Types::Intersection.new(types: [
          AST::Types::Name.new_instance(name: "::Object"),
          AST::Types::Name.new_instance(name: "::String")]),
        ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Intersection.new(types: [
          AST::Types::Name.new_instance(name: "::Object"),
          AST::Types::Name.new_instance(name: "::Integer")
        ]),
        super_type: AST::Types::Name.new_instance(name: "::String")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_equal 1, result.trace.size

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::Object"),
        super_type: AST::Types::Intersection.new(types: [
          AST::Types::Name.new_instance(name: "::Integer"),
          AST::Types::Name.new_instance(name: "::String")]),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
  end

  def test_caching
    checker = new_checker("")

    checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: :"::Object"),
        super_type: AST::Types::Var.new(name: :foo)
      ),
      constraints: Subtyping::Constraints.empty
    )

    # Not cached because the relation has free variables
    assert_empty checker.cache

    checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: :"::Integer"),
        super_type: AST::Types::Name.new_instance(name: :"::Object")
      ),
      constraints: Subtyping::Constraints.empty
    )

    # Cached because the relation does not have free variables
    assert_operator checker.cache,
                    :key?,
                    Subtyping::Relation.new(
                      sub_type: AST::Types::Name.new_instance(name: :"::Integer"),
                      super_type: AST::Types::Name.new_instance(name: :"::Object")
                    )
  end

  def test_resolve1
    checker = new_checker("")

    interface = checker.resolve(AST::Types::Union.new(types: [
      AST::Types::Name.new_instance(name: "::String"),
      AST::Types::Name.new_instance(name: "::Integer")
    ]))

    assert_equal [:class], interface.methods.keys
    assert_equal [AST::Types::Name.new_class(name: "::String", constructor: nil),
                  AST::Types::Name.new_class(name: "::Integer", constructor: nil)],
                 interface.methods[:class].types.map(&:return_type)
  end

  def test_resolve2
    checker = new_checker("")

    interface = checker.resolve(AST::Types::Intersection.new(types: [
      AST::Types::Name.new_instance(name: "::String"),
      AST::Types::Name.new_instance(name: "::Integer")
    ]))

    assert_equal [:class, :to_str, :to_int], interface.methods.keys
    assert_equal [], interface.methods[:class].types
    assert_equal [AST::Types::Name.new_instance(name: "::String")], interface.methods[:to_str].types.map(&:return_type)
    assert_equal [AST::Types::Name.new_instance(name: "::Integer")], interface.methods[:to_int].types.map(&:return_type)
  end

  def test_constraints1
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
end

class B<'a>
  def foo: -> 'a
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B",
                                                  args: [AST::Types::Var.new(name: :x)])
      ),
      constraints: Subtyping::Constraints.new(domain: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :domain?, :x
    assert_empty result.constraints.upper_bound(:x)
    assert_equal [AST::Types::Name.new_instance(name: :"::Integer")], result.constraints.lower_bound(:x)
  end

  def test_constraints2
    checker = new_checker(<<-EOS)
class A<'a>
  def get: -> 'a
  def set: ('a) -> self
end

class B
  def get: -> String
  def set: (String) -> self
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A", args: [AST::Types::Var.new(name: :x)]),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.new(domain: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :domain?, :x
    assert_equal [AST::Types::Name.new_instance(name: :"::String")], result.constraints.upper_bound(:x)
    assert_equal [AST::Types::Name.new_instance(name: :"::String")], result.constraints.lower_bound(:x)

    s = result.constraints.subst(checker)
    assert_equal AST::Types::Name.new_instance(name: :"::String"), AST::Types::Var.new(name: :x).subst(s)
  end

  def test_constraints3
    checker = new_checker(<<-EOS)
class A<'a>
  def set: ('a) -> self
end

class B
  def get: -> String
  def set: (String) -> self
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A", args: [AST::Types::Var.new(name: :x)])
      ),
      constraints: Subtyping::Constraints.new(domain: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :domain?, :x
    assert_equal [AST::Types::Name.new_instance(name: :"::String")], result.constraints.upper_bound(:x)
    assert_empty result.constraints.lower_bound(:x)

    s = result.constraints.subst(checker)
    assert_equal AST::Types::Name.new_instance(name: :"::String"), AST::Types::Var.new(name: :x).subst(s)
  end

  def test_constraints4
    checker = new_checker(<<-EOS)
class A<'a>
  def set: ('a) -> self
end

class B
  def set: (String) -> self
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A", args: [AST::Types::Var.new(name: :x)]),
        super_type: AST::Types::Name.new_instance(name: "::B"),
      ),
      constraints: Subtyping::Constraints.new(domain: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :domain?, :x
    assert_equal [AST::Types::Name.new_instance(name: :"::String")], result.constraints.lower_bound(:x)
    assert_empty result.constraints.upper_bound(:x)

    s = result.constraints.subst(checker)
    assert_equal AST::Types::Name.new_instance(name: :"::String"), AST::Types::Var.new(name: :x).subst(s)
  end
end