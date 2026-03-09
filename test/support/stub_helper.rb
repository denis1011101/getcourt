module StubHelper
  def stub_singleton(target, method_name, callable, &block)
    sc = target.singleton_class
    had = sc.method_defined?(method_name) || sc.private_method_defined?(method_name)
    orig = sc.instance_method(method_name) if had
    fn = callable.respond_to?(:call) ? callable : ->(*) { callable }
    sc.define_method(method_name) { |*a, **kw, &b| fn.call(*a, **kw, &b) }
    block.call
  ensure
    had ? sc.define_method(method_name, orig) : sc.remove_method(method_name)
  end
end
