class RbVmomi::VIM::Folder
  def child_types
    spec = {
      :objectSet => [
        {
          :obj => self,
          :skip => true,
          :selectSet => [
            RbVmomi::VIM::TraversalSpec(
              :path => 'childEntity',
              :type => 'Folder'
            )
          ]
        }
      ],
      :propSet => [
        {
          :type => 'ManagedEntity',
          :pathSet => %w(name),
        }
      ]
    }

    results = @soap.propertyCollector.RetrieveProperties(:specSet => [spec])

    Hash[results.map { |r| [r['name'], r.obj.class] }]
  end

  def traverse_one arc
    @soap.searchIndex.FindChild :entity => self, :name => arc
  end

  def ls_children
    spec = {
      :objectSet => [
        {
          :obj => self,
          :skip => true,
          :selectSet => [
            RbVmomi::VIM::TraversalSpec(
              :path => 'childEntity',
              :type => 'Folder'
            )
          ]
        }
      ],
      :propSet => [
        {
          :type => 'ManagedEntity',
          :pathSet => %w(name),
        }
      ]
    }

    results = @soap.propertyCollector.RetrieveProperties(:specSet => [spec])

    Hash[results.map { |r| [r['name'], r.obj] }]
  end

  def self.ls_properties
    %w(name)
  end

  def self.ls_text r
    "/"
  end
end
