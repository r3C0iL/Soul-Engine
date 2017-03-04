#pragma once

#include "Display\Window\Window.h"
#include "Raster Engine\Shader.h"
#include "Raster Engine\RasterJob.h"

enum BackendName { OpenGL, Vulkan};


namespace RasterBackend {

		/////////////////////////////////////////
		/*         Backend Definitions         */
		/////////////////////////////////////////

	class Backend {
	public:
		Backend();
		~Backend();

		virtual void SetWindowHints(GLFWwindow*&) = 0;
		virtual void BuildWindow(GLFWwindow*) = 0;
		virtual void Draw(GLFWwindow*,RasterJob*) = 0;
		virtual void ResizeWindow(GLFWwindow*, int, int) = 0;

		template<typename Fn,
			typename ... Args>
			void RasterFunction( Fn && fn, Args && ... args) = 0;

	private:
	};

	namespace detail {
		extern std::unique_ptr<Backend> raster;
		extern BackendName backend;
	}
	

		/////////////////////////////////////////
		/*         Public Definitions         */
		/////////////////////////////////////////


	void Init();

	//needs to be called from the main thread
	void SetWindowHints(GLFWwindow*&);

	Shader* CreateShader(const std::string&, shader_t);

	RasterJob* CreateJob();

	template<typename Fn,
		typename ... Args>
		void RasterFunction( Fn && fn, Args && ... args) {
		/*if (glfwVulkanSupported() == GLFW_TRUE) {
		return new VulkanShader(fileName, shaderT);
		}
		else {*/
		static_cast<OpenGLBackend*>(detail::raster.get())->RasterFunction(fn, std::forward<Args>(args)...);
		/*}*/

	}

	void ResizeWindow(GLFWwindow*, int, int);

	void BuildWindow(GLFWwindow*);

	void Terminate();

	void Draw(GLFWwindow*,RasterJob*);
}
