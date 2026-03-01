Pagy::OPTIONS[:limit] = 12

# Pagy >= 43 removed `pagy_array`; keep compatibility with existing controllers.
class Pagy
  Method.module_eval do
    define_method :pagy_array do |collection, **options|
      pagy(:offset, collection, **options)
    end
    protected :pagy_array
  end
end
